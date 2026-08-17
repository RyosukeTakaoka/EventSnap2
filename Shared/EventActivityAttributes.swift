//
//  EventActivityAttributes.swift
//  EventSnap
//
//  Live Activity(Dynamic Island / ロック画面)の状態定義。
//  このファイルはEventSnap2ターゲットとEventSnapWidgetターゲットの両方に含まれる。
//  メインアプリがActivity<EventActivityAttributes>を開始・更新・終了し、
//  EventSnapWidget側のActivityConfigurationがこの型を使って表示を組み立てる。
//

import ActivityKit
import Foundation

/// イベント1件分のLive Activity。
///
/// **目的**: 「カメラ撮影中」のような常時表示ではなく、「イベントが今進行している」
/// ことをDynamic Island / ロック画面から感じられるようにする。写真そのものは
/// 表示に含めない(プライバシー・更新頻度の両面から、数字とひとことのフレーズだけにする)。
struct EventActivityAttributes: ActivityAttributes {
    /// Activity開始時に固定される情報(Live Activityの生存期間中は変わらない)
    let eventID: String

    struct ContentState: Codable, Hashable {
        var eventName: String
        var participantCount: Int
        var photoCount: Int
        var phase: Phase
    }

    /// Live Activityが表す「今の局面」。数字の増減だけでなく、
    /// 局面が変わったこと自体を短いフレーズで伝える。
    enum Phase: String, Codable, Hashable {
        /// 📸 イベント進行中(参加人数・写真枚数を表示)
        case inProgress
        /// ✨ 新しいEvent Reelが生成された直後
        case newMemory
        /// ✨ イベント終了後、Event Reelが用意できている
        case ended
    }
}

// MARK: - 表示用の文言(Dynamic Island・ロック画面で共通利用)

extension EventActivityAttributes.ContentState {
    var icon: String {
        switch phase {
        case .inProgress: return "📸"
        case .newMemory, .ended: return "✨"
        }
    }

    /// 「1 PEOPLE」のような不自然な英語を避け、単数/複数を正しく出し分ける。
    var subline: String {
        switch phase {
        case .inProgress:
            let people = max(participantCount, 1)
            let photos = max(photoCount, 1)
            let peopleWord = people == 1 ? "PERSON" : "PEOPLE"
            let photoWord = photos == 1 ? "PHOTO" : "PHOTOS"
            return "\(people) \(peopleWord) · \(photos) \(photoWord)"
        case .newMemory:
            return "新しい思い出ができました"
        case .ended:
            return "Event Reel ready"
        }
    }
}
