//
//  EventSnapClipApp.swift
//  EventSnapClip
//
//  App Clipのエントリーポイント。
//
//  App Clipは「その場でイベントの様子を覗ける呼び水」であり、フルアプリの
//  代わりではない。撮影・イベントへの参加・投稿はすべてフルアプリだけの機能とし、
//  App ClipではQRコードから読み取ったイベントの今の様子（写真・Event Reel風の
//  プレビュー）を閲覧専用で見せ、続きをしようとした瞬間に「続きはアプリで」と
//  案内する（EventSnapClipRootView参照）。
//
//  そのためCloudKitのPublic Databaseを読み取り専用で使用する
//  （EventPreviewLoader.swift参照）。書き込みはこのターゲットのどこにも
//  存在しない。Universal LinkのURL解析・CloudKit読み取りのハンドリングは
//  EventSnapClipRootView側に持たせているため、ここでは何もしない。
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
