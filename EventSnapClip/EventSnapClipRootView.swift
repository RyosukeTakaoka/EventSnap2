//
//  EventSnapClipRootView.swift
//  EventSnapClip
//
//  App Clipの画面。
//
//  ## なぜ「案内だけ」なのか
//
//  一時期、QRコードから読み取ったイベントの今の様子（写真・Event Reel風の
//  プレビュー）をその場で見せる閲覧専用の体験を実装していた。しかし
//  **App ClipではCloudKitを使えない**。App ClipのApp IDにはiCloudの
//  capability自体が存在せず、entitlementを書くと署名の時点で失敗する
//  （EventSnapClip.entitlementsのコメント参照）。EventSnapのイベント・写真は
//  すべてCloudKitのPublic Databaseにあるため、App Clipからは
//  **イベント名すら取得できない**。
//
//  そのためApp Clipはネットワークアクセスを一切持たず、「EventSnapのイベントに
//  招待された」ことを伝えてフルアプリへ送り出すだけの画面にしている。
//  写真を見る・撮る・イベントに参加する、はすべてフルアプリの機能。
//
//  インストール後は、同じQRコード（＝同じUniversal Link）をもう一度読むと
//  フルアプリ側の`EventSnapApp.handleUniversalLink`がイベント参加まで進む。
//

import SwiftUI

struct EventSnapClipRootView: View {
    var body: some View {
        GetAppScreen(showsCloseButton: false)
    }
}

#Preview {
    EventSnapClipRootView()
}
