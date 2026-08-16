//
//  EventSnapClipApp.swift
//  EventSnapClip
//
//  App Clipのエントリーポイント。
//
//  App Clipは「その場でカメラを試せる呼び水」であり、フルアプリの代わりではない。
//  イベントへの参加・写真の投稿・アルバム閲覧はすべてフルアプリだけの機能とし、
//  App Clipでは撮影だけを体験してもらい、投稿しようとした瞬間に
//  「続きはアプリで」と案内する（EventSnapClipRootView参照）。
//
//  そのためCloudKit・iCloudコンテナへの依存は一切持たせていない。
//  写真はこの場限りのメモリ上にしか存在せず、CloudKitへの書き込みも行わない。
//

import SwiftUI

@main
struct EventSnapClipApp: App {
    var body: some Scene {
        WindowGroup {
            EventSnapClipRootView()
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    // QRコード・Safariのスマートバナー経由での起動。
                    // イベントIDが取れても表示上の演出以外には使わない
                    // （App ClipはCloudKitを読みに行かない設計のため）。
                }
        }
    }
}
