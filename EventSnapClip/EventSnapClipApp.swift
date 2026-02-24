//
//  EventSnapClipApp.swift
//  EventSnapClip
//
//  App Clipのエントリーポイント
//

import SwiftUI

@main
struct EventSnapClipApp: App {
    @StateObject private var eventViewModel = EventViewModel()

    var body: some Scene {
        WindowGroup {
            EventSnapClipView()
                .environmentObject(eventViewModel)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let incomingURL = userActivity.webpageURL else {
                        print("❌ URLが見つかりません")
                        return
                    }

                    print("📥 App Clip起動 URL: \(incomingURL)")

                    // URLからイベントIDを抽出
                    // 想定URL: https://eventsnap.example.com/event/{eventID}
                    if let eventID = extractEventID(from: incomingURL) {
                        print("✅ イベントID抽出成功: \(eventID)")
                        Task {
                            await eventViewModel.joinEvent(eventID: eventID)
                        }
                    } else {
                        print("❌ イベントIDの抽出に失敗しました")
                    }
                }
        }
    }

    /// URLからイベントIDを抽出
    private func extractEventID(from url: URL) -> String? {
        // URLパターン: https://eventsnap.example.com/event/{eventID}
        let components = url.pathComponents

        // "/event/{eventID}" の形式を想定
        if components.count >= 3 && components[1] == "event" {
            return components[2]
        }

        // クエリパラメータからの抽出も対応
        // 例: https://eventsnap.example.com/?eventID={eventID}
        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = urlComponents.queryItems,
           let eventIDItem = queryItems.first(where: { $0.name == "eventID" }),
           let eventID = eventIDItem.value {
            return eventID
        }

        return nil
    }
}
