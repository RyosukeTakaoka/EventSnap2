//
//  ShareCollageView.swift
//  EventSnap
//
//  コラージュ画像のプレビューと共有
//

import SwiftUI

struct ShareCollageView: View {
    let event: Event

    @StateObject private var store = ShareCollageStore.shared
    @State private var collage: UIImage?
    @State private var isBuilding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let collage {
                    Image(uiImage: collage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .padding(.horizontal)

                    if let fileURL = store.fileURL(for: event.id) {
                        ShareLink(
                            item: fileURL,
                            preview: SharePreview("\(event.name) の思い出", image: Image(uiImage: collage))
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

                    Text("シェアが許可された写真だけを使っています")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                } else if isBuilding {
                    ProgressView("コラージュを作成中...")
                        .padding(.vertical, 80)

                } else {
                    emptyState
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("シェア画像")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            collage = store.load(for: event.id)

            // 保存済みが無ければこの場で作ってみる
            if collage == nil {
                isBuilding = true
                collage = await ShareCollageBuilder.buildIfPossible(for: event)
                isBuilding = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                .font(.system(size: 52))
                .foregroundColor(.secondary)

            Text("シェアできる写真がありません")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("撮影時に「シェアOK」を選んだ写真だけがコラージュに使われます。\nこのイベントにはまだ1枚もありません。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }
}
