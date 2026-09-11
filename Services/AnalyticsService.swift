import FirebaseAnalytics
import Foundation

/// Firebase Analyticsへの薄いラッパー。
///
/// `docs/DEFENSIBILITY.md` §4で定義した6指標（Join Rate・First Photo Rate・
/// Contribution Rate・Reel Generation Rate・Reel Share Rate・Repeat Organizer Rate）
/// を実測するために最小限のイベントだけを送る。イベント名・パラメータ名を増やすときは、
/// まずそれがどの指標に効くかを先に確認すること。
enum AnalyticsService {

    /// イベントを作った。`isRepeatOrganizer`は、この端末が過去にも
    /// イベントを作ったことがあるかどうか（Repeat Organizer Rateの分子）。
    static func eventCreated(isRepeatOrganizer: Bool) {
        log("event_created", params: ["is_repeat_organizer": isRepeatOrganizer])
    }

    /// QR/App Clip経由でイベントに参加した（Join Rateの分子）。
    static func eventJoined() {
        log("event_joined", params: [:])
    }

    /// 写真を撮影・アップロードした。`isFirstPhotoForParticipant`は、
    /// このイベントで自分がまだ1枚も撮っていなかったか
    /// （First Photo Rate / Contribution Rateの分子）。
    static func photoCaptured(isFirstPhotoForParticipant: Bool, isTimeCapsule: Bool) {
        log("photo_captured", params: [
            "is_first_photo_for_participant": isFirstPhotoForParticipant,
            "is_time_capsule": isTimeCapsule,
        ])
    }

    /// Event Reelが新しく生成された（Reel Generation Rateの分子）。
    static func eventReelGenerated(reelCount: Int) {
        log("event_reel_generated", params: ["reel_count": reelCount])
    }

    /// Event Reelの共有シートを開いた（Reel Share Rateの近似値）。
    ///
    /// `ShareLink`はSwiftUI標準APIのため、実際に送信完了したかまでは
    /// 取得できない。タップした事実だけを計測する（Rotashの
    /// `workShareCompleted`のような完了判定はここでは作れない）。
    static func eventReelShareTapped(photoCount: Int) {
        log("event_reel_share_tapped", params: ["photo_count": photoCount])
    }

    private static func log(_ name: String, params: [String: Any]) {
        #if DEBUG
        print("📊 \(name) \(params)")
        #endif
        Analytics.logEvent(name, parameters: params)
    }
}
