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

    /// 「✨ NEW MEMORY」表示を保つ上限時間(フォールバック)。
    ///
    /// この間に次の写真が撮られなければ、ここでタイムアウトして通常表示に戻す。
    /// 以前は20秒固定だったが短すぎて見逃されやすかったため延ばした。
    /// ただし無期限表示は「イベント中に写真を増やしてもらう」という
    /// Live Activity本来の目的(進行中フィードバック)を損なうため、
    /// あくまで上限として扱う。実際にはこれより先に`updateCounts`側の
    /// 早期リターン(次の写真が撮られた、という自然な合図)で戻ることが多い。
    private static let newMemoryDisplayDuration: UInt64 = 60 * 1_000_000_000

    /// `notifyReelGenerated`の呼び出し世代。短い間隔で複数のEvent Reelが
    /// 連続生成された場合、古い呼び出しのタイムアウトが新しい呼び出しの
    /// NEW MEMORY表示を巻き込んで消してしまわないようにするための番号。
    @MainActor
    private static var newMemoryGeneration = 0

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

    /// 新しいEvent Reelが生成された直後に呼ぶ。一時的に「✨ NEW MEMORY」を見せる。
    ///
    /// **「見せること」自体が目的ではない**。あくまで「EventSnapが裏側で写真を
    /// まとめて、新しい思い出を作った」という進行中のフィードバックなので、
    /// 通常表示へ戻る条件は2通りに分けている:
    /// 1. **自然な条件(主)**: 次の写真が撮られると`updateCounts`が呼ばれ、
    ///    photoCountが変わった時点で即座に(このタイムアウトを待たずに)
    ///    通常表示へ戻る。「もう次の瞬間が始まっている」という一番自然な合図。
    /// 2. **タイムアウト(保険)**: 次の写真がしばらく撮られない場合に備えて、
    ///    `newMemoryDisplayDuration`だけ待ったら通常表示へ戻す。無期限表示を避けるため。
    static func notifyReelGenerated(eventID: UUID, eventName: String, participantCount: Int, photoCount: Int) async {
        guard let activity = current, activity.attributes.eventID == eventID.uuidString else { return }

        let myGeneration = await MainActor.run { () -> Int in
            newMemoryGeneration += 1
            return newMemoryGeneration
        }

        let newMemoryState = EventActivityAttributes.ContentState(
            eventName: eventName, participantCount: participantCount, photoCount: photoCount, phase: .newMemory
        )
        await activity.update(.init(state: newMemoryState, staleDate: nil))

        try? await Task.sleep(nanoseconds: newMemoryDisplayDuration)

        // 待っている間に別のEvent Reelが新しく生成されていたら(=世代が進んでいたら)、
        // そちらの表示・タイムアウトに譲って何もしない(古い世代が新しい世代の
        // NEW MEMORY表示を巻き込んで消してしまうのを防ぐ)。
        let stillLatestGeneration = await MainActor.run { newMemoryGeneration == myGeneration }
        guard stillLatestGeneration else { return }

        // 待っている間に次の写真が撮られてphotoCountが変わっていれば、
        // `updateCounts`側で既に通常表示へ戻っているはず。ここではその後に
        // 何も変わっていない場合(=タイムアウトで戻す必要がある場合)にだけ戻す。
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
