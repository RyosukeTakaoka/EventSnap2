//
//  EventSnapDeepLink.swift
//  EventSnap
//
//  Widget / Live Activityのタップ遷移先URLを組み立てる。
//  このファイルはEventSnap2ターゲットとEventSnapWidgetターゲットの両方に含まれる。
//

import Foundation

/// `eventsnap://` カスタムURLスキームでの内部ディープリンク。
///
/// 既存のUniversal Link(`https://eventsnap-website.vercel.app/event/{eventID}`、
/// `AppLinkConfig`参照)はQRコード/App Clip経由の「参加」専用の入口であり、これとは
/// 役割が異なる。こちらはアプリが既に端末にインストールされている前提の、
/// Widget/Live Activityから「今見ているイベントを開き直す」ための内部リンクなので、
/// 既存のUniversal Link設計には一切手を入れず、別スキームとして追加する。
enum EventSnapDeepLink {
    static let scheme = "eventsnap"

    enum Destination: Equatable {
        /// 指定イベントの画面を開く
        case event(eventID: UUID)
        /// 指定イベントの、指定Event Reel(シェア画面)を開く
        case eventReel(eventID: UUID, reelID: UUID)
        /// 指定イベントのTime Capsuleタブを開く
        case timeCapsule(eventID: UUID)
        /// 指定イベントのカメラ(撮影画面)を直接開く。Live Activityのシャッターボタン用。
        case camera(eventID: UUID)
    }

    static func url(for destination: Destination) -> URL? {
        switch destination {
        case .event(let eventID):
            return URL(string: "\(scheme)://event/\(eventID.uuidString)")
        case .eventReel(let eventID, let reelID):
            return URL(string: "\(scheme)://event/\(eventID.uuidString)/reel/\(reelID.uuidString)")
        case .timeCapsule(let eventID):
            return URL(string: "\(scheme)://event/\(eventID.uuidString)/timecapsule")
        case .camera(let eventID):
            return URL(string: "\(scheme)://event/\(eventID.uuidString)/camera")
        }
    }

    /// Widgetの共有状態から、タップ時に開くべき最も自然な行き先を決める。
    /// 最新Event Reelがあればそこへ、無ければイベント画面へ。
    static func url(for state: EventSnapSharedState.State) -> URL? {
        guard let eventID = state.eventID else { return nil }
        if let reelID = state.latestReelID {
            return url(for: .eventReel(eventID: eventID, reelID: reelID))
        }
        return url(for: .event(eventID: eventID))
    }

    /// 受け取ったURLを解析する。`eventsnap://`以外は`nil`を返す
    /// (Universal Linkは`EventSnapApp.handleUniversalLink`が別途処理する)。
    static func parse(_ url: URL) -> Destination? {
        guard url.scheme == scheme, url.host == "event" else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard let idString = parts.first, let eventID = UUID(uuidString: idString) else { return nil }

        if parts.count >= 3, parts[1] == "reel", let reelID = UUID(uuidString: parts[2]) {
            return .eventReel(eventID: eventID, reelID: reelID)
        }
        if parts.count >= 2, parts[1] == "timecapsule" {
            return .timeCapsule(eventID: eventID)
        }
        if parts.count >= 2, parts[1] == "camera" {
            return .camera(eventID: eventID)
        }
        return .event(eventID: eventID)
    }
}
