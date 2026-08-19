//
//  AlbumView.swift
//  EventSnap
//
//  アルバム画面
//

import SwiftUI

struct AlbumView: View {
    @StateObject private var viewModel = AlbumViewModel()
    /// MainTabView から共有されるインスタンスを受け取る。
    /// 以前はここで @StateObject を作っていたため、タブごとに別のイベント状態を
    /// 持ってしまい、グループを切り替えても反映されなかった。
    @ObservedObject var eventViewModel: EventViewModel
    @Binding var showEventSwitcher: Bool
    @StateObject private var collageStore = ShareCollageStore.shared
    @ObservedObject private var tutorial = TutorialManager.shared

    /// アルバム画面が扱う初回チュートリアルのステップ
    /// （カメラ側のステップは`CameraView`が別途面倒を見る）。
    private static let albumSteps: Set<TutorialStep> = [.albumGrid, .lockedPhoto, .notificationHint]

    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.items.isEmpty {
                    // 空の状態
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("まだ写真がありません")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("カメラで撮影すると\nここに自動的に表示されます")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // 写真グリッド。タイムカプセルでまだ公開されていない写真は、
                    // プレビューできないグレーの枠として同じグリッドに混ぜて並べる
                    // （砂時計マークで見分ける）。
                    let firstLockedID = viewModel.locked.first?.id
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(viewModel.items) { item in
                            switch item {
                            case .revealed(let photo):
                                NavigationLink(destination: PhotoDetailView(photo: photo, viewModel: viewModel)) {
                                    PhotoCell(photo: photo, viewModel: viewModel)
                                }
                            case .locked(let photo):
                                LockedPhotoCell(photo: photo, isTutorialTarget: photo.id == firstLockedID)
                            }
                        }
                    }
                    .tutorialTarget(.albumGrid)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // タイトルをタップするとイベントを切り替えられる
                ToolbarItem(placement: .principal) {
                    Button {
                        showEventSwitcher = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(eventViewModel.currentEvent?.name ?? "アルバム")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 以前はここに写真枚数を表示するだけの、タップしても何も起きない
                // ラベルを置いていた。Event Reelへの入口として機能を持たせる。
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let event = eventViewModel.currentEvent {
                        NavigationLink {
                            ShareCollageView(event: event)
                        } label: {
                            // アイコンに明示的なフレームを持たせてからバッジを重ねる。
                            // タイトなグリフのバウンディングボックスに対してバッジを
                            // .offsetではみ出させると、ナビゲーションバー側のクリップで
                            // 見えなくなったり、画面遷移時に残像として残ったりするため
                            // （UnreadBadge.swiftのコメント参照）、先に余裕のある
                            // フレームを確保しておく。
                            Image(systemName: "square.and.arrow.up.on.square")
                                .font(.system(size: 17))
                                .frame(width: 30, height: 30)
                                .unreadBadge(collageStore.unseenReelCount(for: event.id))
                        }
                        .accessibilityLabel("Event Reel")
                    }
                }
            }
            .refreshable {
                await viewModel.fetchPhotos()
            }
        }
        // 初回チュートリアル: 実際のグリッド・公開待ちの枠をハイライトするだけで、
        // 偽物のUIは作らない（`TutorialManager`のコメント参照）。
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            if let step = tutorial.currentStep, Self.albumSteps.contains(step) {
                let content = step.content
                TutorialSpotlightOverlay(
                    manager: tutorial,
                    anchors: anchors,
                    target: content.target,
                    title: content.title,
                    message: content.message,
                    actionLabel: content.actionLabel,
                    onAdvance: { tutorial.advance(hasLockedPhotos: !viewModel.locked.isEmpty) }
                )
            }
        }
        .task {
            await viewModel.fetchPhotos()
            await viewModel.setupRealtimeSync()
        }
    }
}

// MARK: - 写真セル

struct PhotoCell: View {
    let photo: Photo
    let viewModel: AlbumViewModel

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if isLoading {
                        // ローディング表示
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let image = image {
                        // 実際の画像を表示
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        // エラー表示
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            // グリッド全体が真四角のタイル敷き詰めだと硬い印象になるため、
            // ごく小さい角丸だけ付けて柔らかく見せる（Instagramのグリッドに近い調整）。
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // 「あとで公開」の写真が公開された直後だけ、写真を邪魔しない
                // 小さなNEWバッジを添える。一定時間で自動的に消える
                // （`TimeCapsuleService.isRecentlyRevealed`参照）ので、
                // アルバムは最終的に普通の思い出アルバムに戻る。
                if TimeCapsuleService.isRecentlyRevealed(photo) {
                    NewlyRevealedBadge()
                }
            }
            .task {
                await loadImage()
            }
    }

    private func loadImage() async {
        print("📥 画像ダウンロード開始: \(photo.id)")
        
        isLoading = true
        
        let downloadedImage = await viewModel.downloadImage(for: photo)
        
        if let downloadedImage = downloadedImage {
            self.image = downloadedImage
            print("✅ 画像ダウンロード成功: \(photo.id)")
        } else {
            print("❌ 画像ダウンロード失敗: \(photo.id)")
        }
        
        isLoading = false
    }
}

// MARK: - タイムカプセルのロック枠

/// タイムカプセルでまだ公開されていない写真の枠。
/// 中身はプレビューできない（タップ不可）。参加者全員が同じ枠を見る。
///
/// グレーのまま何も出さないと「画像が正しく読み込めていない」ように見えてしまうため、
/// 待機中であることが一目で分かるアイコンと、ぼかした残り時間（`vagueCountdown`）を添えている。
struct LockedPhotoCell: View {
    let photo: Photo
    var isTutorialTarget: Bool = false

    var body: some View {
        Rectangle()
            // 単色のグレーだと「読み込み失敗」に見えるため、DesignTokensの
            // ゴールド系グラデーションで「これから届く」ワクワク感を出す
            // （Widget/Event Reelと統一したブランドカラーの一部）。
            .fill(DesignTokens.capsuleGradient)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // アイコンだけだと初見のユーザーには何のセルか伝わらないため、
                // ゴールド背景の上に白文字でテキストも添える。
                // カウントダウンの文言はVoiceOver向けにaccessibilityLabelへ残す。
                VStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.title2)
                    Text("公開まで\nお待ちください")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundColor(.white)
                .padding(4)
            }
            // PhotoCellと角丸を揃え、グリッド上で浮いて見えないようにする
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .tutorialTarget(.lockedPhoto, isActive: isTutorialTarget)
            .accessibilityLabel("公開前のタイムカプセル写真。\(TimeCapsuleService.vagueCountdown(for: photo))")
    }
}

// MARK: - 最近公開されたバッジ

/// 「あとで公開」の写真が公開された直後だけ表示する、小さなNEWバッジ。
/// 写真そのものより目立たせず、隅に添えるだけに留める。
struct NewlyRevealedBadge: View {
    var body: some View {
        Text("✨ NEW")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                LinearGradient(colors: [Color.pink, Color.orange], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .padding(5)
            .accessibilityLabel("最近公開された写真")
    }
}

// MARK: - 写真詳細ビュー

struct PhotoDetailView: View {
    let photo: Photo
    let viewModel: AlbumViewModel
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var showingSaveConfirmation = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()

                // 実際の画像を表示
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                    } else if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("画像の読み込みに失敗しました")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // 写真情報。以前は背景に何も無い白文字だけだったため、明るい写真の上では
                // 読みにくかった。すりガラス調のカプセルに乗せて、どんな写真の上でも
                // 視認性を確保する。
                infoCard
                    .padding(.bottom, 20)
            }

            // 上部はナビゲーションバーのボタンが写真に埋もれて見づらくなることがあるため、
            // ごく薄いスクリムを敷いて視認性を底上げする。
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.45), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 110)
                .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    saveImageToPhotos()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                }
                .disabled(image == nil)
            }
        }
        .task {
            await loadImage()
        }
        .alert("保存完了", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("写真をカメラロールに保存しました")
        }
    }
    
    // MARK: - 写真情報カード

    private var infoCard: some View {
        HStack(spacing: 14) {
            Label {
                Text(photo.uploadedAt.formatted(date: .abbreviated, time: .shortened))
            } icon: {
                Image(systemName: "calendar")
            }

            if let filterName = photo.filterName {
                Divider()
                    .frame(height: 12)
                    .overlay(Color.white.opacity(0.35))

                Label {
                    Text(filterName)
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
            }
        }
        .font(.caption)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func loadImage() async {
        print("📥 詳細画像ダウンロード開始: \(photo.id)")
        
        isLoading = true
        
        let downloadedImage = await viewModel.downloadImage(for: photo)
        
        if let downloadedImage = downloadedImage {
            self.image = downloadedImage
            print("✅ 詳細画像ダウンロード成功")
        } else {
            print("❌ 詳細画像ダウンロード失敗")
        }
        
        isLoading = false
    }
    
    private func saveImageToPhotos() {
        guard let image = image else { return }
        
        print("💾 カメラロールに保存開始...")
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showingSaveConfirmation = true
        
        print("✅ カメラロールに保存完了")
    }
}

// MARK: - 公開通知タップ時のフルスクリーン表示

/// 公開通知をタップしたときに開く、対象写真のフルスクリーン表示。
///
/// 通常のアルバムを開くだけでなく、「今公開されたその写真」を直接、画面いっぱいに
/// 見せる（`MainTabView`が`EventViewModel.pendingRevealPhotoID`を見てこれを
/// `fullScreenCover`として提示する）。写真を主役にし、説明文は最小限に留める。
struct RevealedPhotoFullScreenView: View {
    let photo: Photo
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.7))
                    Text("画像の読み込みに失敗しました")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    .padding(.trailing, 16)
                    .accessibilityLabel("閉じる")
                }
                .padding(.top, 8)

                Spacer()

                HStack {
                    Spacer()
                    NewlyRevealedBadge()
                        .padding(.trailing, 10)
                        .padding(.bottom, 24)
                }
            }
        }
        .task {
            image = await PhotoImageLoader.shared.image(for: photo)
            isLoading = false
        }
    }
}

#Preview {
    AlbumView(eventViewModel: EventViewModel(), showEventSwitcher: .constant(false))
}
