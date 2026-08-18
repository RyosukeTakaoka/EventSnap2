//
//  ShareCollageBuilder.swift
//  EventSnap
//
//  イベント中に育っていくEvent Reelの生成の段取り
//

import Foundation
import UIKit
import WidgetKit

/// 「シェアOKのまだ使っていない写真を複数枚選ぶ → 品質と多様性を見て2〜5枚に絞る →
/// SocialCardServiceで1枚の複数写真Event Reelにする → 履歴に追加保存する」
/// という一連の流れをまとめたもの。
///
/// イベント終了を待たず、**イベント中に**新しいシェアOK写真がまとまった量
/// 集まるたびに新しいEvent Reelを作る。古いReelは上書きせず、履歴として残す
/// （3〜5枚のまとまり → Reel #1、次のまとまり → Reel #2、…と育っていく）。
///
/// 以前は「シェアOK写真1枚につきReelを1個」作っていたが、それだと数十枚集まる
/// イベントでは数十個のReelが並んでしまう。`EventReelPhotoSelector`が
/// 品質・多様性を見て複数枚をまとめて選ぶことで、1つのReelが「その時間帯の
/// 代表的な思い出」を表すようにし、Reelの総数を写真枚数よりずっと少なく抑える。
///
/// Event Reelは固定スナップショットではない。写真のシェアOKが後からOFFに
/// なった場合は `removeFromReels` で該当Reelの中身を更新する。
enum ShareCollageBuilder {

    /// この枚数の未使用シェアOK写真が集まって初めて、新しいEvent Reelの生成を試みる。
    /// これ未満では「まだ十分な思い出が集まっていない」として待つ。
    static let minPhotosForNewReel = 3

    /// 実際にEvent Reelとして保存する最小枚数(重複除去後)。
    ///
    /// `minPhotosForNewReel`枚の未使用写真が集まっても、同一撮影者の連写や
    /// 似た構図が`EventReelPhotoSelector`によって束ねられた結果、選び出せる
    /// 枚数がそれより少なくなることがある(例: 3枚集まっても同じ人の連写で
    /// 2枚に、あるいは1枚にまとまってしまう)。ここで`minPhotosForNewReel`と
    /// 同じ値を要求すると、そのバーストが解消されるまで永久にEvent Reelが
    /// 生成されないまま`remaining`に居座り続けてしまう(「3枚集まっても
    /// 生成されない」という不具合の原因)。`MultiPhotoRenderer`は1枚からでも
    /// レイアウトできる設計のため、2枚まで束ねられていれば意味のある
    /// Reelとして成立するとみなし、そこで妥協して生成する。
    static let minSelectedPhotosPerReel = 2

    /// 1件のEvent Reelに入れる写真の上限。「7枚や10枚を無理に詰め込まない」
    /// という方針のための上限で、これを超える分は次のReelの材料として残る。
    static let maxPhotosPerReel = 5

    /// 1回のビルドで解析(Vision)にかける候補の上限。取りこぼし分は次回の
    /// `buildIfNeeded`で改めて古い順から拾われるため、無制限に増やす必要はない。
    /// Vision解析はメインアクター上で同期的に行われるため、あまり大きくすると
    /// 一度に多くの写真が溜まった端末でUIが一時的に固まりうる（詳細は末尾コメント）。
    private static let analysisPoolCap = 12

    /// イベント中の自動生成チェック。
    ///
    /// 写真がアップロードされた・定期同期が走った・写真がシェアOKにされた、
    /// といったタイミングで呼ぶ想定。**すでに何らかのReelに使われた写真は候補から除く**
    /// （`ShareCollageStore.usedPhotoIDs`）ため、古い写真が後からシェアOKにされても
    /// 過去のReelを勝手に書き換えることはなく、次のReelの材料になるだけ。
    /// 同期の間隔が空いて一度に大量のシェアOK写真が増えていた場合は、
    /// 取りこぼさないよう作れるだけ複数のReelをまとめて作る。
    ///
    /// - Returns: 実際に生成されたEvent Reel（新しい順）。1件も作らなければ空配列
    @MainActor
    @discardableResult
    static func buildIfNeeded(for event: Event) async -> [EventReel] {
        // 撮影モードでは自動生成しない。Fixtureが用意したEvent Reelを
        // 作り直してしまうと、撮影のたびに中身が変わってしまうため。
        guard !ScreenshotMode.suppressesLiveServices else { return [] }

        // シェアOKとタイムカプセルが両方trueのまま残っている写真は、
        // ここでシェアを優先して解除する。「両立を許し、実際に使う瞬間に解決する」
        // という設計のため、shareApprovedPhotosを読む前に必ず呼ぶこと。
        await PhotoRepository.shared.releaseSharedTimeCapsules(for: event.id)

        let approved = PhotoRepository.shared.shareApprovedPhotos(for: event.id) // 古い順
        let store = ShareCollageStore.shared
        let used = store.usedPhotoIDs(for: event.id)

        var remaining = approved.filter { !used.contains($0.id) }
        var created: [EventReel] = []

        while remaining.count >= minPhotosForNewReel {
            // 古い順から一定数だけを解析対象にする（撮影時間の分散を見る都合上、
            // 常に一番古い未使用写真から評価を始めるのが自然なため）。
            let pool = Array(remaining.prefix(analysisPoolCap))
            let candidates = await analyzeCandidates(pool)

            let target = min(candidates.count, maxPhotosPerReel)
            guard target >= minPhotosForNewReel,
                  let selection = EventReelPhotoSelector.select(from: candidates, target: target),
                  selection.ordered.count >= minSelectedPhotosPerReel
            else {
                // 解析できた枚数が足りない(ダウンロード失敗が続いた等)、または
                // 重複除去後にminSelectedPhotosPerReelすら残らなかった。
                // remainingは変えずに終了し、次回の同期で改めて試す
                // (新しい写真が増えれば束ね方も変わるため)。
                break
            }

            guard let rendered = await renderEventReel(selection: selection, event: event) else {
                print("⚠️ Event Reel用の画像生成に失敗したため、このバッチは今回スキップします")
                break
            }

            do {
                let reel = try store.addReel(rendered.image, for: event.id, photoIDs: rendered.photoIDs)
                created.append(reel)
                notifyNewReel(reel, image: rendered.image, event: event)
            } catch {
                print("❌ Event Reelの保存に失敗: \(error)")
                break
            }

            let usedIDs = Set(rendered.photoIDs)
            remaining.removeAll { usedIDs.contains($0.id) }
        }

        return created
    }

    /// shareOKがOFFに変わった写真を、既存のEvent Reelから取り除く。
    ///
    /// プライバシー保護のための操作（間違えてONにした・写っている人から削除希望が
    /// あった等）。該当する写真を含むReelがあれば、その写真を除いた残りで画像を
    /// 作り直す。残りが0枚になったReelは削除する。`index`・`builtAt` は変えない
    /// （生成した記録自体は保持し、中身だけを更新する）。
    ///
    /// ここでは`EventReelPhotoSelector`による選び直しはしない。すでにそのReelの
    /// 一員として選ばれていた写真たちを、1枚除いてそのまま並べ直すだけ。
    ///
    /// この写真は `shareApprovedPhotos` にもう出てこなくなるため、
    /// 今後生成されるReelにも一切使われない。
    @MainActor
    static func removeFromReels(photoID: UUID, event: Event) async {
        let store = ShareCollageStore.shared
        let affected = store.reels(for: event.id).filter { $0.photoIDs.contains(photoID) }
        guard !affected.isEmpty else { return }

        let photosByID = Dictionary(
            uniqueKeysWithValues: PhotoRepository.shared.shareApprovedPhotos(for: event.id).map { ($0.id, $0) }
        )

        for reel in affected {
            let remainingIDs = reel.photoIDs.filter { $0 != photoID }
            let remainingPhotos = remainingIDs.compactMap { photosByID[$0] }

            do {
                if remainingPhotos.isEmpty {
                    try store.updateReel(reel, newPhotoIDs: [], newImage: nil)
                } else if let rendered = await rerenderExisting(remainingPhotos, event: event) {
                    try store.updateReel(reel, newPhotoIDs: rendered.photoIDs, newImage: rendered.image)
                }
            } catch {
                print("❌ Event Reel #\(reel.index) の更新に失敗: \(error)")
            }
        }
    }

    // MARK: - 代表写真の選定(旧・単写真Reelとの後方互換用)

    /// 写真の集合から、代表として使う1枚を選ぶ（新しい順に、実際に画像取得できるものを探す）。
    ///
    /// **この関数自体は新しいEvent Reel生成では使わない。** アップデート前に
    /// 端末へ保存済みの、写真1枚だけのEvent Reel（`photoIDs.count == 1`）を
    /// `SocialCardShareView`が引き続き表示できるようにするために残してある。
    @MainActor
    static func heroPhoto(from photos: [Photo]) async -> (photo: Photo, image: UIImage)? {
        let ordered = photos.sorted { $0.uploadedAt > $1.uploadedAt }
        for candidate in ordered {
            if let image = await PhotoImageLoader.shared.image(for: candidate) {
                return (candidate, image)
            }
        }
        return nil
    }

    /// 既存のEvent Reelから、代表写真を改めて取得する（後方互換用、上記参照）。
    @MainActor
    static func heroPhoto(for reel: EventReel) async -> (photo: Photo, image: UIImage)? {
        let candidates = PhotoRepository.shared.allPhotos.filter { reel.photoIDs.contains($0.id) }
        return await heroPhoto(from: candidates)
    }

    /// 「瞬間の主」の番号（代表写真の撮影者が参加者の中で何番目に参加したか）。
    /// 後方互換の単写真Reel表示（`SocialCardShareView`）でのみ使用する。
    static func momentInfo(for photo: Photo, event: Event) -> (index: Int, total: Int) {
        let index = (event.participantIDs.firstIndex(of: photo.uploaderID) ?? 0) + 1
        let total = max(event.participantIDs.count, index)
        return (index, total)
    }

    // MARK: - 内部: 複数写真Event Reelの描画

    /// 候補写真をサムネイルで解析する（ダウンロードに失敗したものは候補から除く）。
    ///
    /// フル解像度ではなくサムネイルを使うのは、選定段階では最終的に何枚採用するかも
    /// 決まっておらず、候補全部（最大`analysisPoolCap`枚）を解析する必要があるため。
    /// `PhotoAnalysisResult`の座標はすべて正規化済み([0,1])なので、サムネイルで得た
    /// `importanceCenter`はフル解像度画像にもそのまま使い回せる（本番描画時に
    /// 再解析は不要）。
    @MainActor
    private static func analyzeCandidates(_ photos: [Photo]) async -> [EventReelPhotoSelector.Candidate] {
        var candidates: [EventReelPhotoSelector.Candidate] = []
        for photo in photos {
            guard let thumbnail = await PhotoImageLoader.shared.thumbnail(for: photo) else { continue }
            let analysis = PhotoAnalyzer.analyze(thumbnail)
            candidates.append(EventReelPhotoSelector.Candidate(photo: photo, analysis: analysis))
        }
        return candidates
    }

    /// 選ばれた写真たちを、実際にEvent Reel画像として描画する。
    /// フル解像度画像の取得に失敗した写真は、解析済みのサムネイルにフォールバックする
    /// （選定時点でサムネイルの取得自体には成功しているため、通常はキャッシュ経由で
    /// 即座に手に入る）。1枚も取得できなければ`nil`を返す。
    @MainActor
    private static func renderEventReel(
        selection: EventReelPhotoSelector.Selection,
        event: Event
    ) async -> (image: UIImage, photoIDs: [UUID])? {
        var inputs: [MultiPhotoRenderer.PhotoInput] = []
        var usedIDs: [UUID] = []

        for candidate in selection.ordered {
            var image = await PhotoImageLoader.shared.image(for: candidate.photo)
            if image == nil {
                image = await PhotoImageLoader.shared.thumbnail(for: candidate.photo)
            }
            guard let image else { continue }
            inputs.append(MultiPhotoRenderer.PhotoInput(image: image, importanceCenter: candidate.analysis.importanceCenter))
            usedIDs.append(candidate.photo.id)
        }

        guard !inputs.isEmpty else { return nil }

        // `Event.photoCount`はCloudKit側で更新される仕組みが無く常に0のままなので
        // (アップロード経路のどこにも加算処理が無い)、統計表示にはその場で数え直した
        // 実際の枚数を使う。
        let photoCount = PhotoRepository.shared.allPhotos.filter { $0.eventID == event.id }.count
        let latestDate = selection.ordered.map(\.photo.uploadedAt).max() ?? Date()

        let image = SocialCardService.renderEventReel(
            photos: inputs,
            eventName: event.name,
            date: latestDate,
            participantCount: event.participantIDs.count,
            photoCount: photoCount
        )
        return (image, usedIDs)
    }

    /// 新しいEvent Reelが生成された直後に呼ぶ、Widget/Live Activityへの通知。
    ///
    /// データの流れ: `ShareCollageBuilder` → `ShareCollageStore`(保存済み) →
    /// `EventSnapSharedState`更新(App Group) → `WidgetCenter.reloadTimelines` →
    /// `EventActivityManager`更新、という一方向の流れにする。Widget/Live Activity
    /// 自身がCloudKitやPhotoAnalyzerに触れることは無い。
    ///
    /// `EventActivityManager.notifyReelGenerated`は「✨ NEW MEMORY」を数秒間
    /// 見せてから元に戻すまで内部で待つため、`buildIfNeeded`の完了を
    /// (ひいてはカメラアップロード完了の体感を)ブロックしないよう、
    /// 待たずに`Task`で切り離して呼ぶ。
    @MainActor
    private static func notifyNewReel(_ reel: EventReel, image: UIImage, event: Event) {
        EventSnapSharedState.updateLatestReel(reelID: reel.id, builtAt: reel.builtAt, image: image)
        WidgetCenter.shared.reloadTimelines(ofKind: "EventSnapWidget")

        let participantCount = event.participantIDs.count
        let photoCount = PhotoRepository.shared.allPhotos.filter { $0.eventID == event.id }.count
        Task {
            await EventActivityManager.notifyReelGenerated(
                eventID: event.id, eventName: event.name, participantCount: participantCount, photoCount: photoCount
            )
        }
    }

    /// `removeFromReels`専用: 選び直し(多様性ボーナス等)は再実行せず、渡された
    /// 写真だけを対象に「メインに最も適した1枚を選び、残りを撮影順で」並べ直して
    /// 再描画する。メインの選び方自体は`select`と同じ`EventReelPhotoSelector.pickMain`
    /// を使う(Event Memory Valueを踏まえた選定ロジックを重複させない)。
    @MainActor
    private static func rerenderExisting(_ photos: [Photo], event: Event) async -> (image: UIImage, photoIDs: [UUID])? {
        let candidates = await analyzeCandidates(photos)
        guard !candidates.isEmpty else { return nil }

        let ordered: [EventReelPhotoSelector.Candidate]
        if let main = EventReelPhotoSelector.pickMain(from: candidates) {
            let subs = candidates
                .filter { $0.photo.id != main.photo.id }
                .sorted { $0.photo.uploadedAt < $1.photo.uploadedAt }
            ordered = [main] + subs
        } else {
            ordered = candidates
        }

        return await renderEventReel(selection: EventReelPhotoSelector.Selection(ordered: ordered), event: event)
    }
}
