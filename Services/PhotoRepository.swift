//
//  PhotoRepository.swift
//  EventSnap
//
//  写真データ管理（CloudKit連携）
//

import Foundation
import CloudKit
import UIKit
import Combine

@MainActor
class PhotoRepository: ObservableObject {
    static let shared = PhotoRepository()

    /// アルバムに表示する写真（＝公開済みのもの）。
    /// タイムカプセルで伏せられている写真はここには入らない。
    @Published var photos: [Photo] = []

    /// 取得したすべての写真。タイムカプセルタブが未公開分の枚数を数えるのに使う。
    @Published var allPhotos: [Photo] = []

    @Published var isUploading = false
    @Published var error: Error?

    private let container = CKContainer.default()
    private var database: CKDatabase

    init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - 写真アップロード

    /// 写真をアップロードする
    ///
    /// - Parameters:
    ///   - isShareOK: 撮影者がSNSシェアを許可したか（既定OFF）
    ///   - forceTimeCapsule: 撮影者が明示的に「あとで公開」を選んだか
    /// - Returns: 実際に保存された写真（タイムカプセルになったかどうかを含む）
    @discardableResult
    func uploadPhoto(
        _ image: UIImage,
        eventID: UUID,
        filterName: String? = nil,
        isShareOK: Bool = false,
        forceTimeCapsule: Bool = false
    ) async throws -> Photo {
        isUploading = true
        defer { isUploading = false }

        let deviceID = DeviceIdentity.current
        let capturedAt = Date()

        // 一部の写真を遅延公開に回す（機能A）。シェアOKとの併用を許す。
        // 両方trueになった場合はEvent Reel生成時にシェアを優先して解除する
        // （`releaseSharedTimeCapsules`）。
        let revealDate = TimeCapsuleService.decideRevealDate(
            capturedAt: capturedAt,
            forcedByUser: forceTimeCapsule
        )

        let photo = Photo(
            eventID: eventID,
            uploaderID: deviceID,
            uploaderName: DeviceIdentity.displayName,
            uploadedAt: capturedAt,
            filterName: filterName,
            aiProcessed: filterName != nil,
            isTimeCapsule: revealDate != nil,
            revealDate: revealDate,
            isShareOK: isShareOK
        )

        // ローカルキャッシュに即座に追加（UX向上）。
        // ただしタイムカプセルはアルバムに出さない。伏せた本人にも見せない。
        if !photo.isTimeCapsule {
            self.photos.insert(photo, at: 0)
        }
        self.allPhotos.insert(photo, at: 0)

        // 画像をリサイズ（パフォーマンス向上）
        guard let resizedImage = resizeImage(image, maxSize: 1920) else {
            rollback(photo)
            throw NSError(domain: "PhotoRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "画像のリサイズに失敗"])
        }

        // CloudKitレコード作成
        let record = photo.toRecord()

        // 画像データを一時ファイルに保存
        if let imageData = resizedImage.jpegData(compressionQuality: 0.8) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(photo.id.uuidString).jpg")

            try imageData.write(to: tempURL)
            record["imageAsset"] = CKAsset(fileURL: tempURL)

            // サムネイル生成
            if let thumbnail = resizeImage(resizedImage, maxSize: 300),
               let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) {
                let thumbnailURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(photo.id.uuidString)_thumb.jpg")
                try thumbnailData.write(to: thumbnailURL)
                record["thumbnailAsset"] = CKAsset(fileURL: thumbnailURL)
            }
        }

        do {
            _ = try await database.save(record)
            print("✅ レコードの保存に成功しました")
            return photo
        } catch let error as CKError {
            rollback(photo)
            // CloudKit特有のエラーを処理
            switch error.code {
            case .networkUnavailable, .networkFailure:
                print("❌ ネットワークエラー: インターネット接続を確認してください")
            case .notAuthenticated:
                print("❌ iCloudにサインインしていません")
            case .quotaExceeded:
                print("❌ iCloudストレージの容量が不足しています")
            case .serverRecordChanged:
                print("❌ サーバー上のレコードが変更されています（競合）")
            case .unknownItem:
                print("❌ 保存しようとしたレコードが見つかりません")
            default:
                print("❌ CloudKitエラー: \(error.localizedDescription)")
            }
            self.error = error
            throw error
        } catch {
            rollback(photo)
            print("❌ 写真アップロード失敗: \(error)")
            self.error = error
            throw error
        }
    }

    /// アップロードに失敗した写真をローカルキャッシュから取り除く
    private func rollback(_ photo: Photo) {
        photos.removeAll { $0.id == photo.id }
        allPhotos.removeAll { $0.id == photo.id }
    }

    // MARK: - 写真取得

    /// イベントの写真一覧を取得
    func fetchPhotos(for eventID: UUID) async throws {
        // 撮影モードではCloudKitに問い合わせない（注入済みのFixtureを維持する）
        guard !ScreenshotMode.suppressesLiveServices else { return }

        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Photo", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "uploadedAt", ascending: false)]

        do {
            let results = try await database.records(matching: query)

            var fetchedPhotos: [Photo] = []

            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let photo = Photo.from(record: record) {
                    fetchedPhotos.append(photo)
                }
            }

            self.allPhotos = fetchedPhotos
            // アルバムには公開済みのものだけを流す。
            // 公開判定は revealDate との比較なので、全端末で同じ結果になる。
            self.photos = TimeCapsuleService.albumPhotos(fetchedPhotos)

            let locked = fetchedPhotos.count - self.photos.count
            print("✅ 写真取得成功: 公開済み \(self.photos.count)枚 / 未公開 \(locked)枚")
        } catch {
            print("❌ 写真取得失敗: \(error)")
            self.error = error
            throw error
        }
    }

    /// シェアが許可された写真だけを、撮影順（古い順）に取り出す（Event Reel生成用）。
    ///
    /// シェアOKとタイムカプセルは両立しうるため、`isTimeCapsule` で除外している。
    /// まだ公開されていない（＝タイムカプセルのまま残っている）写真は、
    /// `releaseSharedTimeCapsules` で解除されるまでここには出てこない。
    /// 呼び出し側（`ShareCollageBuilder.buildIfNeeded`）は、このメソッドを呼ぶ前に
    /// 必ず解除処理を先に行うこと。
    /// 古い順に並んでいるのは、Event Reelが古いものから順に1枚ずつ区切られるため。
    func shareApprovedPhotos(for eventID: UUID) -> [Photo] {
        allPhotos
            .filter { $0.eventID == eventID && $0.isShareOK && !$0.isTimeCapsule }
            .sorted { $0.uploadedAt < $1.uploadedAt }
    }

    // MARK: - タイムカプセルの解除（優先ルール）

    /// シェアOKとタイムカプセルが重複した、まだ未公開の写真を通常公開に戻す。
    ///
    /// EventSnapには2つの価値がある:
    ///   - タイムカプセル … 隠すことで未来の価値を作る
    ///   - Event Reel（シェア） … 公開することで今の価値を最大化する
    ///
    /// 両立できる状態は許すが、実際にEvent Reelへ使う瞬間には解決が要る。
    /// **イベント直後〜イベント中の共有価値を優先する**と決めているので、
    /// ここで呼ばれた時点で対象の写真は問答無用でタイムカプセルから外れ、
    /// 通常のアルバム写真として全員に公開される。
    ///
    /// `ShareCollageBuilder.buildIfNeeded` が `shareApprovedPhotos` を読む前に
    /// 必ず呼ぶ。単体では呼ばない（Event Reelに使われないのに公開だけ早まる、
    /// という中途半端な状態を作らないため）。
    ///
    /// - Returns: 実際に解除された写真
    @discardableResult
    func releaseSharedTimeCapsules(for eventID: UUID) async -> [Photo] {
        let targets = allPhotos.filter {
            $0.eventID == eventID
                && $0.isShareOK
                && $0.isTimeCapsule
                && !$0.isRevealed()   // 既に公開済みのものは触らない
        }

        guard !targets.isEmpty else { return [] }

        print("🔓 シェア優先: \(targets.count)枚のタイムカプセルを解除します")

        var released: [Photo] = []

        for photo in targets {
            var updated = photo
            updated.isTimeCapsule = false
            updated.revealDate = nil

            do {
                try await save(updated)
                released.append(updated)
            } catch {
                print("❌ タイムカプセルの解除に失敗 (\(photo.id)): \(error)")
            }
        }

        guard !released.isEmpty else { return [] }

        let releasedByID = Dictionary(uniqueKeysWithValues: released.map { ($0.id, $0) })
        allPhotos = allPhotos.map { releasedByID[$0.id] ?? $0 }
        photos = TimeCapsuleService.albumPhotos(allPhotos)

        // 公開予定が無くなったので、予約済みの通知も取り消す
        await NotificationService.shared.cancelReveals(for: released.map(\.id))

        return released
    }

    // MARK: - シェアOK状態の変更

    /// 撮影後に「シェアOK」の状態を変更する。
    ///
    /// 想定ケース: 間違えてONにした／写っている人から削除希望があった／
    /// SNS共有を取り消したい、など。**タイムカプセルの状態
    /// （`isTimeCapsule`・`revealDate`）には一切影響しない**。
    ///
    /// - OFFにした場合: 既存のEvent Reelからもこの写真を取り除き、画像を作り直す
    ///   （`ShareCollageBuilder.removeFromReels`）。以後の`shareApprovedPhotos`にも
    ///   出てこなくなるため、今後生成されるReelにも一切使われない
    /// - ONにした場合: 次回以降のEvent Reel生成の対象に加わる
    ///   （`ShareCollageBuilder.buildIfNeeded`）。まだ公開されていない
    ///   タイムカプセル写真であっても指定できる。その場合、写真自体はまだ非公開の
    ///   ままで、実際にEvent Reelへ使われる瞬間（`releaseSharedTimeCapsules`）に
    ///   初めて公開される（このメソッドを呼んだだけでは公開されない）
    ///
    /// - Returns: 更新後の写真。変更不要／失敗した場合は nil
    @discardableResult
    func setShareOK(_ isShareOK: Bool, for photo: Photo, event: Event) async -> Photo? {
        guard photo.isShareOK != isShareOK else { return photo }

        var updated = photo
        updated.isShareOK = isShareOK

        do {
            try await save(updated)
        } catch {
            print("❌ シェアOK状態の更新に失敗 (\(photo.id)): \(error)")
            self.error = error
            return nil
        }

        if let index = allPhotos.firstIndex(where: { $0.id == photo.id }) {
            allPhotos[index] = updated
        }
        if let index = photos.firstIndex(where: { $0.id == photo.id }) {
            photos[index] = updated
        }

        if isShareOK {
            print("📤 シェアOKにしました: \(photo.id)")
            await ShareCollageBuilder.buildIfNeeded(for: event)
        } else {
            print("🔒 シェアOKを取り消しました: \(photo.id)")
            await ShareCollageBuilder.removeFromReels(photoID: photo.id, event: event)
        }

        return updated
    }

    /// 写真を更新する（既存レコードを取得してから上書きする）。
    ///
    /// 新規に `CKRecord` を作り直すと recordID が変わって複製になるため、
    /// 更新時は既存レコードを取り直してから書き込む。
    ///
    /// まず `recordID` で直接取得する（強い一貫性）。クエリ
    /// （`records(matching:)`）は結果整合なので、保存した直後の写真は
    /// インデックスに載るまで見つからず、更新のつもりが新規作成＝複製に
    /// なってしまうことがある。旧バージョンが作った recordName がランダムな
    /// レコードだけ、見つからない場合にクエリへフォールバックする。
    private func save(_ photo: Photo) async throws {
        do {
            let existing = try await database.record(for: photo.recordID)
            _ = try await database.save(photo.apply(to: existing))
            return
        } catch let error as CKError where error.code == .unknownItem {
            // 旧形式のレコードかもしれないのでフィールド検索に落とす
        }

        let predicate = NSPredicate(format: "id == %@", photo.id.uuidString)
        let query = CKQuery(recordType: "Photo", predicate: predicate)
        let results = try await database.records(matching: query)

        if let (_, result) = results.matchResults.first,
           let existing = try? result.get() {
            _ = try await database.save(photo.apply(to: existing))
        } else {
            _ = try await database.save(photo.toRecord())
        }
    }

    // MARK: - リアルタイム更新

    /// CloudKit Subscriptionを設定（リアルタイム同期）
    func setupSubscription(for eventID: UUID) async {
        // 撮影モードではサブスクリプションを作らない
        guard !ScreenshotMode.suppressesLiveServices else { return }

        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let subscription = CKQuerySubscription(
            recordType: "Photo",
            predicate: predicate,
            subscriptionID: "photo-added-\(eventID.uuidString)",
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        // サイレントプッシュ。受け取った端末が写真一覧を取り直し、
        // 未公開のタイムカプセルに対してローカル通知を予約し直す。
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            print("✅ リアルタイム同期設定完了")
        } catch {
            print("❌ Subscription設定失敗: \(error)")
        }
    }

    // MARK: - ヘルパーメソッド

    /// 画像リサイズ
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)

        // 十分小さい場合でも向きだけは確定させてから返す。
        // ここで生の UIImage を返すと、orientation を持ったまま JPEG 化され、
        // 経路によっては向きが失われる。
        if ratio >= 1 { return image.normalizedUp() }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        format.opaque = true

        // draw(in:) は imageOrientation を解釈して描くので、
        // 出来上がりは常に .up の正しい向きになる。
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
