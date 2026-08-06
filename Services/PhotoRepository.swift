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

        // 一部の写真を遅延公開に回す（機能A）
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

    /// シェアが許可された写真だけを取り出す（コラージュ生成用・機能B）
    func shareApprovedPhotos(for eventID: UUID) -> [Photo] {
        allPhotos
            .filter { $0.eventID == eventID && $0.isShareOK }
            .sorted { $0.uploadedAt < $1.uploadedAt }
    }

    // MARK: - タイムカプセルの解除（優先ルール）

    /// シェアOKとタイムカプセルが重複した写真を、通常公開の写真に戻す。
    ///
    /// EventSnapには2つの価値がある:
    ///   - タイムカプセル … 隠すことで未来の価値を作る
    ///   - シェアコラージュ … 公開することで現在の価値を最大化する
    ///
    /// 両立できないので、**イベント終了直後の共有価値を優先する**と決めた。
    /// 拡散効果が最も高いのはイベント直後であり、その機会を逃さないことを取る。
    /// ユーザーに二択を迫らず、アプリ側が自動で役割を決める。
    ///
    /// - Returns: 実際に解除された写真
    @discardableResult
    func releaseSharedTimeCapsules(for eventID: UUID) async -> [Photo] {
        let targets = allPhotos.filter {
            $0.eventID == eventID && $0.isShareOK && $0.isTimeCapsule
        }

        guard !targets.isEmpty else { return [] }

        print("🔓 シェア優先: \(targets.count)枚のタイムカプセルを解除します")

        var released: [Photo] = []

        for photo in targets {
            let updated = photo.releasedFromTimeCapsule()
            do {
                try await save(updated)
                released.append(updated)
            } catch {
                print("❌ タイムカプセルの解除に失敗 (\(photo.id)): \(error)")
            }
        }

        guard !released.isEmpty else { return [] }

        // ローカルの状態を差し替える。解除された写真はアルバムにも並ぶようになる。
        let releasedByID = Dictionary(uniqueKeysWithValues: released.map { ($0.id, $0) })
        allPhotos = allPhotos.map { releasedByID[$0.id] ?? $0 }
        photos = TimeCapsuleService.albumPhotos(allPhotos)

        // 公開予定が無くなったので、予約済みの通知も取り消す
        await NotificationService.shared.cancelReveals(for: released.map(\.id))

        return released
    }

    /// 写真を保存する（既存があれば上書き、無ければ新規作成）。
    ///
    /// 新規に `CKRecord` を作り直すと recordID が変わって複製になるため、
    /// 更新時は既存レコードを取り直してから書き込む。
    private func save(_ photo: Photo) async throws {
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
