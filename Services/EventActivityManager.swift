//
//  EventActivityManager.swift
//  EventSnap
//
//  イベントの進行状況をDynamic Island / ロック画面のLive Activityとして表示する。
//

import ActivityKit
import Foundation

/// **目的**: 「カメラ撮影中」のような常時表示ではなく、「イベントが今進行している」
/// ことをDynamic Island / ロック画面から感じられるようにする。
///
/// **やらないこと**: 写真そのものの表示、頻繁な画像更新、CloudKitへの直接アクセス、
/// リモートプッシュでの更新。`SyncCoordinator`が同期した結果(参加人数・写真枚数)を
/// 渡してもらい、その状態をそのまま反映するだけの受動的なマネージャーにする
/// （プッシュを使わないため`Activity.request`の`pushType`は指定しない）。
enum EventActivityManager {

    /// 「✨ NEW MEMORY」表示を保つ時間。この間だけ見せてから、通常の進行中表示に戻す。
    private static let newMemoryDisplayDuration: UInt64 = 20 * 1_000_000_000

    private static var current: Activity<EventActivityAttributes>? {
        Activity<EventActivityAttributes>.activities.first
    }

    // MARK: - 開始

    /// イベント開始時、またはアプリ復帰時にLive Activityが無ければ開始する。
    /// 既に同じイベントのActivityが動いていれば何もしない(二重生成しない)。
    static func startIfNeeded(event: Event, participantCount: Int, photoCount: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let current {
            if current.attributes.eventID == event.id.uuidString {
                return // 既に同じイベントで動作中
            }
            // 別イベントに切り替わった場合は、古いActivityを閉じてから開始し直す
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = EventActivityAttributes(eventID: event.id.uuidString)
        let state = EventActivityAttributes.ContentState(
            eventName: event.name, participantCount: participantCount, photoCount: photoCount, phase: .inProgress
        )

        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            print("❌ Live Activityの開始に失敗: \(error)")
        }
    }

    // MARK: - 更新

    /// 参加人数・写真枚数が変わったときに呼ぶ。数字が変わっていなければ更新しない
    /// (過剰更新を避ける)。
    static func updateCounts(eventID: UUID, eventName: String, participantCount: Int, photoCount: Int) async {
        guard let activity = current, activity.attributes.eventID == eventID.uuidString else { return }
        let old = activity.content.state
        guard old.participantCount != participantCount || old.photoCount != photoCount else { return }

        let state = EventActivityAttributes.ContentState(
            eventName: eventName, participantCount: participantCount, photoCount: photoCount, phase: .inProgress
        )
        await activity.update(.init(state: state, staleDate: nil))
    }

    /// 新しいEvent Reelが生成された直後に呼ぶ。一時的に「✨ NEW MEMORY」を見せてから、
    /// 自動で通常の進行中表示に戻す(3〜5枚集まるごとの生成であり、写真1枚ごとではないため、
    /// 通知疲れになるほどの頻度にはならない)。
    static func notifyReelGenerated(eventID: UUID, eventName: String, participantCount: Int, photoCount: Int) async {
        guard let activity = current, activity.attributes.eventID == eventID.uuidString else { return }

        let newMemoryState = EventActivityAttributes.ContentState(
            eventName: eventName, participantCount: participantCount, photoCount: photoCount, phase: .newMemory
        )
        await activity.update(.init(state: newMemoryState, staleDate: nil))

        try? await Task.sleep(nanoseconds: newMemoryDisplayDuration)

        // 待っている間に別の更新(イベント終了など)が起きていなければ、進行中表示に戻す
        guard let stillCurrent = current, stillCurrent.id == activity.id,
              stillCurrent.content.state.phase == .newMemory
        else { return }

        let backToProgress = EventActivityAttributes.ContentState(
            eventName: eventName, participantCount: participantCount, photoCount: photoCount, phase: .inProgress
        )
        await stillCurrent.update(.init(state: backToProgress, staleDate: nil))
    }

    // MARK: - 終了

    /// イベント終了時に呼ぶ。「✨ Event Reel ready」を最終状態として見せたまま、
    /// システムに任せて数時間後に自動で片付けさせる(`dismissalPolicy: .default`)。
    static func markEnded(eventID: UUID, eventName: String, participantCount: Int, photoCount: Int) async {
        guard let activity = current, activity.attributes.eventID == eventID.uuidString else { return }

        let state = EventActivityAttributes.ContentState(
            eventName: eventName, participantCount: participantCount, photoCount: photoCount, phase: .ended
        )
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
    }

    /// イベントから離脱した・別グループに切り替えた場合に、進行中のActivityを即座に閉じる。
    static func endImmediately(eventID: UUID) async {
        guard let activity = current, activity.attributes.eventID == eventID.uuidString else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
