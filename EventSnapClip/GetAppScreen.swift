//
//  GetAppScreen.swift
//  EventSnapClip
//
//  App Clipの唯一の画面。EventSnapのイベントに招待されたことを伝え、
//  フルアプリへ送り出す。
//
//  App ClipはCloudKitを使えないため、イベント名や写真といった中身は
//  一切取得できない（EventSnapClipRootViewのコメント参照）。
//  ここで見せられるのは「これはEventSnapの招待である」という案内だけ。
//

import SwiftUI

struct GetAppScreen: View {
    /// 右上に「閉じる」を出すか。
    /// App Clipのルート画面として使うときは戻り先が無いので `false`。
    var showsCloseButton: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let appStoreURL = URL(
        string: "https://apps.apple.com/jp/app/eventsnapapp/id6762540308"
    )!

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundColor(.blue)

                VStack(spacing: 10) {
                    Text("EventSnapに招待されました")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("EventSnapは、その場にいるみんなで撮った写真が\n1つのアルバムに自動で集まるアプリです。\n無料でダウンロードできます。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    openURL(appStoreURL)
                } label: {
                    Text("App Storeからダウンロード")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)

                Text("ダウンロードしたら、もう一度QRコードを読み取ると\nそのイベントに参加できます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
        }
        // iPadでは NavigationView が既定で2カラムの分割表示になり、
        // 中身がサイドバー側に押し込まれて見えなくなるため、スタック表示に固定する。
        .navigationViewStyle(.stack)
    }
}
