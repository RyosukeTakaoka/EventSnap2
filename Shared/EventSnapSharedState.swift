//
//  EventSnapSharedState.swift
//  EventSnap
//
//  メインアプリとWidget/Live Activity Extensionが共有する、イベントの「今の状態」。
//  このファイルはEventSnap2ターゲットとEventSnapWidgetターゲットの両方に含まれる。
//

import Foundation
import UIKit

/// **設計方針**: WidgetやLive ActivityがCloudKitやPhotoAnalyzerに直接触れることは
/// 一切ない（重い処理・大量データの取得はメインアプリ側でのみ発生させる）。
/// メインアプリが同期・生成した結果を、ここでApp Group内にミラーするだけにする。
/// Widget/Live Activityはこの共有状態を読むだけの受動的な存在にする
/// （`EventActivityManager`・`SyncCoordinator`を参照）。
///
/// 写真そのものを無制限にApp Groupへコピーしない。共有するのは最新Event Reelの
/// 縮小プレビュー1枚だけ（`latestReelPreviewFileName`）。それ以外の写真本体・
/// shareOK OFFの写真・Time Capsule未公開写真はここに一切書き込まない
/// （Privacyの詳細は`updateLatestReel`のコメントを参照）。
enum EventSnapSharedState {

    static let appGroupID = "group.app.takaoka.com.EventSnap2"

    private static let defaultsKey = "eventSnapSharedState.v1"
    private static let previewSubdirectory = "WidgetPreviews"

    enum EventState: String, Codable {
        /// 参加中のイベントが無い
        case none
        /// イベント進行中
        case active
        /// イベント終了（Reelは引き続き閲覧・共有できる）
        case ended
    }

    struct State: Codable, Equatable {
        var eventID: UUID?
        var eventName: String?
        var participantCount: Int
        var photoCount: Int
        var latestReelID: UUID?
        var latestReelPreviewFileName: String?
        var latestReelCreatedAt: Date?
        var timeCapsuleLockedCount: Int
        var eventState: EventState
        var updatedAt: Date

        static let empty = State(
            eventID: nil,
            eventName: nil,
            participantCount: 0,
            photoCount: 0,
            latestReelID: nil,
            latestReelPreviewFileName: nil,
            latestReelCreatedAt: nil,
            timeCapsuleLockedCount: 0,
            eventState: .none,
            updatedAt: Date()
        )
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    // MARK: - 読み込み(Widget/Live Activity/メインアプリ共通)

    static func load() -> State {
        guard let defaults,
              let data = defaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return .empty }
        return state
    }

    /// 最新Event Reelの縮小プレビュー画像。無ければ`nil`(Widget側は「まだReelが無い」表示にする)。
    static func latestReelPreviewImage() -> UIImage? {
        guard let fileName = load().latestReelPreviewFileName,
              let containerURL
        else { return nil }
        let url = containerURL.appendingPathComponent(previewSubdirectory).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - 更新(メインアプリのみが呼ぶ)
    //
    // このファイルはEventSnap2ターゲットとEventSnapWidgetターゲットの両方に
    // 含まれるため、ここから先の関数は`Event`・`EventReel`(Modelsグループ、
    // メインアプリターゲット限定)を直接受け取らず、呼び出し側(メインアプリ側)で
    // 取り出した値だけを渡してもらう。そうしないとWidget側のビルドが
    // 「型が見つからない」で失敗する。

    /// イベントの基本状態(参加人数・写真枚数・タイムカプセル残数)を更新する。
    /// `SyncCoordinator`が同期のたびに呼ぶ想定。`eventID`が`nil`は「参加中のイベントが無い」。
    static func updateEventState(
        eventID: UUID?,
        eventName: String?,
        participantCount: Int,
        isActive: Bool,
        photoCount: Int,
        timeCapsuleLockedCount: Int
    ) {
        var state = load()

        if let eventID {
            state.eventID = eventID
            state.eventName = eventName
            state.participantCount = participantCount
            state.eventState = isActive ? .active : .ended
        } else {
            state.eventID = nil
            state.eventName = nil
            state.participantCount = 0
            state.eventState = .none
        }
        state.photoCount = photoCount
        state.timeCapsuleLockedCount = timeCapsuleLockedCount
        state.updatedAt = Date()

        save(state)
    }

    /// 新しいEvent Reelが生成された直後に呼ぶ。
    ///
    /// **Privacy**: ここで共有するのはshareOK済みの写真だけから`MultiPhotoRenderer`が
    /// 生成した完成済みのEvent Reel画像であり、個別の写真そのものではない。
    /// 元画像を縮小してJPEG化するだけで、追加のフィルタ・加工はしない。
    /// 古いプレビューは保持せず、常に最新の1枚だけを残す(`purgeOldPreviews`)。
    static func updateLatestReel(reelID: UUID, builtAt: Date, image: UIImage) {
        var state = load()
        state.latestReelID = reelID
        state.latestReelCreatedAt = builtAt
        state.latestReelPreviewFileName = writePreview(image, reelID: reelID)
        state.updatedAt = Date()
        save(state)
    }

    private static func save(_ state: State) {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// Widgetは小さくしか表示しないため、元画像をそのまま置かず縮小してから
    /// App Group共有コンテナに書き出す。
    private static func writePreview(_ image: UIImage, reelID: UUID) -> String? {
        guard let containerURL else { return nil }
        let previewDir = containerURL.appendingPathComponent(previewSubdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        let maxDimension: CGFloat = 640
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = resized.jpegData(compressionQuality: 0.75) else { return nil }

        let fileName = "\(reelID.uuidString).jpg"
        let fileURL = previewDir.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            purgeOldPreviews(keeping: fileName, in: previewDir)
            return fileName
        } catch {
            print("❌ Widget用プレビューの書き出しに失敗: \(error)")
            return nil
        }
    }

    /// 過去のプレビューファイルが共有コンテナに溜まらないよう、最新の1枚以外は消す。
    private static func purgeOldPreviews(keeping fileName: String, in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent != fileName {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
