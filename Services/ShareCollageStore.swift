//
//  ShareCollageStore.swift
//  EventSnap
//
//  生成したEvent Reel画像のローカル保存（イベントごとの履歴）
//

import Foundation
import UIKit

/// 生成したEvent Reelをアプリ内に置いておき、後からでも見返せるようにする。
///
/// CloudKitには上げない。Event Reelは各自の端末で同じ素材（シェアOKの写真）から
/// 組み立てられるものであり、共有ストレージに置くと「シェアOKにしていない写真が
/// 混ざっていないか」を検証できる場所が増えてしまうため。
///
/// **古いReelは上書きせず、履歴として複数保存する**。イベント中にシェアOKの写真が
/// 増えるたびに新しいReelが増え、「#1」「#2」「#3」…と育っていく体験にする。
///
/// **完全な固定スナップショットではない**。写真のシェアOKが後からOFFになった場合は
/// 該当するReelの中身（`photoIDs` と画像）を更新する（`ShareCollageBuilder` から呼ばれる）。
/// 生成した記録（`index`・`builtAt`）自体は保持し、中身だけが現在のシェアOK状態を反映する。
@MainActor
final class ShareCollageStore: ObservableObject {
    static let shared = ShareCollageStore()

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ShareCollages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func imageURL(for reelID: UUID) -> URL {
        directory.appendingPathComponent("\(reelID.uuidString).jpg")
    }

    private func reelsKey(for eventID: UUID) -> String {
        "eventReels_\(eventID.uuidString)"
    }

    private func lastSeenKey(for eventID: UUID) -> String {
        "eventReelsLastSeen_\(eventID.uuidString)"
    }

    // MARK: - 未読管理（LINEのような通知バッジに使う）

    /// 最後に確認したEvent Reelの番号(index)。まだ一度も見ていなければ0。
    func lastSeenReelIndex(for eventID: UUID) -> Int {
        UserDefaults.standard.integer(forKey: lastSeenKey(for: eventID))
    }

    /// まだ見ていないEvent Reelの件数。
    /// `index`は生成順に振られる連番なので、これより大きいものが「新着」。
    func unseenReelCount(for eventID: UUID) -> Int {
        let seen = lastSeenReelIndex(for: eventID)
        return reels(for: eventID).filter { $0.index > seen }.count
    }

    /// Event Reel一覧を開いたときに呼ぶ。全て読んだことにしてバッジを消す。
    func markReelsSeen(for eventID: UUID) {
        let latest = reels(for: eventID).map(\.index).max() ?? 0
        guard latest > lastSeenReelIndex(for: eventID) else { return }
        UserDefaults.standard.set(latest, forKey: lastSeenKey(for: eventID))
        objectWillChange.send()
    }

    // MARK: - 履歴の読み書き

    /// このイベントのEvent Reel一覧（新しい順）
    func reels(for eventID: UUID) -> [EventReel] {
        guard let data = UserDefaults.standard.data(forKey: reelsKey(for: eventID)),
              let reels = try? JSONDecoder().decode([EventReel].self, from: data)
        else { return [] }
        return reels.sorted { $0.index > $1.index }
    }

    func hasAnyReel(for eventID: UUID) -> Bool {
        !reels(for: eventID).isEmpty
    }

    /// これまでに何らかのReelに使われたことのある写真ID（イベント全体）。
    /// `ShareCollageBuilder` が次のReelを作る際、まだ使われていない写真だけを
    /// 候補にするために使う。
    func usedPhotoIDs(for eventID: UUID) -> Set<UUID> {
        reels(for: eventID).reduce(into: Set<UUID>()) { $0.formUnion($1.photoIDs) }
    }

    /// 新しいEvent Reelを履歴に追加保存する（既存のReelは一切変更・削除しない）
    @discardableResult
    func addReel(_ image: UIImage, for eventID: UUID, photoIDs: [UUID]) throws -> EventReel {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CollageError.encodingFailed
        }

        let nextIndex = (reels(for: eventID).map(\.index).max() ?? 0) + 1
        let reel = EventReel(eventID: eventID, index: nextIndex, photoIDs: photoIDs)

        try data.write(to: imageURL(for: reel.id), options: .atomic)

        var updated = reels(for: eventID)
        updated.append(reel)
        saveReels(updated, for: eventID)

        print("💾 Event Reel #\(reel.index) を保存しました: \(eventID.uuidString)")
        objectWillChange.send()
        return reel
    }

    /// 既存のReelの中身を更新する（shareOKが取り消された写真を除いた結果に差し替える）。
    ///
    /// `newPhotoIDs` が空（＝全ての写真が取り消された）なら、Reelごと削除する。
    /// `index`・`builtAt` はそのまま維持する。生成した記録自体は保持し、
    /// 中身だけを「現在のシェアOK状態」に合わせて更新する、という扱いのため。
    func updateReel(_ reel: EventReel, newPhotoIDs: [UUID], newImage: UIImage?) throws {
        var all = reels(for: reel.eventID)
        guard let index = all.firstIndex(where: { $0.id == reel.id }) else { return }

        guard !newPhotoIDs.isEmpty, let newImage else {
            try? FileManager.default.removeItem(at: imageURL(for: reel.id))
            all.remove(at: index)
            saveReels(all, for: reel.eventID)
            print("🗑 Event Reel #\(reel.index) を削除しました（対象写真が0枚になったため）")
            objectWillChange.send()
            return
        }

        guard let data = newImage.jpegData(compressionQuality: 0.92) else {
            throw CollageError.encodingFailed
        }
        try data.write(to: imageURL(for: reel.id), options: .atomic)

        all[index].photoIDs = newPhotoIDs
        saveReels(all, for: reel.eventID)

        print("🔄 Event Reel #\(reel.index) を更新しました（\(newPhotoIDs.count)枚）")
        objectWillChange.send()
    }

    func image(for reel: EventReel) -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL(for: reel.id)) else { return nil }
        return UIImage(data: data)
    }

    /// 共有シートに渡すためのファイルURL（画像そのものより取り回しが良い）
    func fileURL(for reel: EventReel) -> URL? {
        let url = imageURL(for: reel.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// イベントのEvent Reelをすべて削除する（イベントを離脱したときなど）
    func deleteAll(for eventID: UUID) {
        for reel in reels(for: eventID) {
            try? FileManager.default.removeItem(at: imageURL(for: reel.id))
        }
        UserDefaults.standard.removeObject(forKey: reelsKey(for: eventID))
        UserDefaults.standard.removeObject(forKey: lastSeenKey(for: eventID))
        objectWillChange.send()
    }

    private func saveReels(_ reels: [EventReel], for eventID: UUID) {
        guard let data = try? JSONEncoder().encode(reels) else { return }
        UserDefaults.standard.set(data, forKey: reelsKey(for: eventID))
    }
}

enum CollageError: LocalizedError {
    case noApprovedPhotos
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noApprovedPhotos:
            return "シェアが許可された写真がありません"
        case .encodingFailed:
            return "Event Reel画像の保存に失敗しました"
        }
    }
}
