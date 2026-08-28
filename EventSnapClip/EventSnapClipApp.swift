//
//  EventSnapClipApp.swift
//  EventSnapClip
//
//  App Clipのエントリーポイント。
//
//  App ClipはCloudKitを使えないため（EventSnapClip.entitlements参照）、
//  イベントの中身は一切取得できない。EventSnapのイベントに招待されたことを
//  伝えてフルアプリへ送り出すだけの案内画面を出す。
//  撮影・閲覧・イベントへの参加はすべてフルアプリだけの機能。
//

import SwiftUI

@main
struct EventSnapClipApp: App {
    var body: some Scene {
        WindowGroup {
            EventSnapClipRootView()
        }
    }
}
