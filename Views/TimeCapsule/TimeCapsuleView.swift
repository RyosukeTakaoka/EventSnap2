//
//  TimeCapsuleView.swift
//  EventSnap
//
//  タイムカプセル（遅延公開）タブ。
//  参加者全員が同じ枚数・同じ待ち時間を共有する（個人単位の機能ではない）
//

import SwiftUI

struct TimeCapsuleView: View {
    @StateObject private var viewModel = TimeCapsuleViewModel()
    @StateObject private var collageStore = ShareCollageStore.shared
    @ObservedObject var eventViewModel: EventViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.lockedCount > 0 {
                        lockedBanner
                    }

                    if viewModel.revealed.isEmpty {
                        emptyState
                    } else {
                        revealedGrid
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("タイムカプセル")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let shareEntry = eventViewModel.currentEvent,
                       collageStore.hasAnyReel(for: shareEntry.id) {
                        NavigationLink {
                            ShareCollageView(event: shareEntry)
                        } label: {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - 未公開のお知らせ

    /// 参加者全員が同じ枚数を共有する。誰が撮ったかに関わらず、
    /// 中身は revealDate が来るまで**誰にも**見えない。
    private var lockedBanner: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.85), Color.pink.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)

                Image(systemName: "hourglass")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("\(viewModel.lockedCount)枚の思い出が眠っています")
                .font(.headline)

            Text("参加者みんなで、公開の瞬間を待っています")
                .font(.caption)
                .foregroundColor(.secondary)

            // 正確な公開日時は見せない。「いつ来るか分からない」ことが
            // アプリを開く理由になるため、ぼかした表現に留める。
            if let hint = viewModel.nextRevealHint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("公開されると通知でお知らせします")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.systemGray6))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    // MARK: - 公開済み

    private var revealedGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("公開された思い出")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.revealed) { photo in
                    NavigationLink {
                        TimeCapsuleDetailView(photo: photo, viewModel: viewModel)
                    } label: {
                        TimeCapsuleCell(photo: photo, viewModel: viewModel)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 54))
                .foregroundColor(.secondary)

            Text(viewModel.lockedCount > 0 ? "まだ公開された写真はありません" : "タイムカプセルはまだありません")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(viewModel.lockedCount > 0
                 ? "公開まで楽しみに待ちましょう"
                 : "撮影時に「あとで公開」を選ぶと、\nしばらく経ってから参加者全員に公開される思い出になります")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal)
    }
}

// MARK: - セル

struct TimeCapsuleCell: View {
    let photo: Photo
    let viewModel: TimeCapsuleViewModel

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.secondary)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .padding(4)
            }
            .clipped()
            .task {
                image = await viewModel.image(for: photo)
                isLoading = false
            }
    }
}

// MARK: - 詳細

struct TimeCapsuleDetailView: View {
    let photo: Photo
    let viewModel: TimeCapsuleViewModel

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().tint(.white).scaleEffect(1.5)
                }

                Spacer()

                VStack(spacing: 6) {
                    if let name = photo.uploaderName, !name.isEmpty {
                        Text("\(name)さんの思い出")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    Text("撮影: \(photo.uploadedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    if let revealDate = photo.revealDate {
                        Text("公開: \(revealDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            image = await PhotoImageLoader.shared.image(for: photo)
        }
    }
}
