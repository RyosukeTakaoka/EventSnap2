//
//  GetAppScreen.swift
//  EventSnapClip
//

import SwiftUI
import StoreKit

struct GetAppScreen: View {
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
                    Text("続きはアプリで")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("この写真をイベントの参加者と共有するには、\nEventSnapアプリが必要です。\n無料でダウンロードできます。")
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

                Spacer()
            }
            .navigationBarItems(
                trailing: Button("閉じる") {
                    dismiss()
                }
            )
        }
    }
}
