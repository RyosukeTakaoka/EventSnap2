//
//  ShareCollageView.swift
//  EventSnap
//
//  Event Reel（イベント中に育っていくシェア画像）の履歴表示と共有
//

import SwiftUI

struct ShareCollageView: View {
    let event: Event

    @StateObject private var store = ShareCollageStore.shared
    @State private var reels: [EventReel] = []
    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                if reels.isEmpty {
                    if isChecking {
                        ProgressView("Event Reelを確認中...")
                            .padding(.vertical, 80)
                    } else {
                        emptyState
                    }
                } else {
                    ForEach(reels) { reel in
                        ReelCard(reel: reel, eventName: event.name, store: store)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Event Reel")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            reels = store.reels(for: event.id)

            // 溜まっている新着シェアOK写真が無いか、この場でも確認する
            isChecking = true
            await ShareCollageBuilder.buildIfNeeded(for: event)
            reels = store.reels(for: event.id)
            isChecking = false

            // 開いたので未読バッジを消す（LINEの既読と同じ考え方）
            store.markReelsSeen(for: event.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                .font(.system(size: 52))
                .foregroundColor(.secondary)

            Text("Event Reelはまだありません")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("撮影時に「シェアOK」を選んだ写真が\(ShareCollageBuilder.photosPerReel)枚集まると、\nイベント中に自動でEvent Reelが作られます。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }
}

// MARK: - 1件分のカード

private struct ReelCard: View {
    let reel: EventReel
    let eventName: String
    let store: ShareCollageStore

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Event Reel #\(reel.index)")
                    .font(.headline)
                Spacer()
                Text(reel.builtAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.horizontal)

                if let fileURL = store.fileURL(for: reel) {
                    ShareLink(
                        item: fileURL,
                        preview: SharePreview("\(eventName) の思い出", image: Image(uiImage: image))
                    ) {
                        Label("シェアする", systemImage: "square.and.arrow.up")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
        .task {
            image = store.image(for: reel)
        }
    }
}
