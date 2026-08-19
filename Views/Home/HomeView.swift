//
//  HomeView.swift
//  EventSnap
//
//  ホーム画面
//

import SwiftUI

struct HomeView: View {
    @StateObject private var eventViewModel = EventViewModel()
    // MainTabViewを出すかどうかは、EventViewModel経由の間接的な状態ではなく
    // EventRepository.shared（真の情報源）から直接判定する。
    // 別インスタンスのEventViewModel同士が同期しきれない可能性を排除するため。
    @ObservedObject private var eventRepository = EventRepository.shared
    @State private var showQRScanner = false
    @State private var showEventCreation = false
    @State private var eventName = ""

    var body: some View {
        // ⑥ 招待+読み取りの合成カットは、通常のHomeView→MainTabViewの導線とは
        // 別物（QRコードとスキャン画面を重ねた専用View）なので、このシーンの
        // ときだけ丸ごと差し替える。それ以外のシーン・通常起動では影響しない。
        if ScreenshotMode.isActive && ScreenshotMode.scene == .inviteOverlay {
            QROverlayScreenshotView()
        } else {
        NavigationView {
            ZStack {
                // 背景は白（ごく薄いDesignTokens.primaryのティント）。
                // 一時期DesignTokens.primaryの単色ベタ塗りにしていたが、
                // 「新しいイベントを作成」ボタンやQRファインダー枠のような
                // ブランドカラーの要素が背景に溶けて見づらくなったため、
                // 白背景の上にそれらの要素だけ単色で乗せる形に戻す。
                DesignTokens.primary.opacity(0.06)
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 32) {
                            Spacer(minLength: 24)

                            titleSection

                            qrFinderSection

                            actionsSection

                            // イベント終了は「そのイベントだけ」に効く操作。
                            // タイトル画面に戻っても、他に参加しているイベントには
                            // すぐ入れるよう一覧を出しておく。
                            if !eventViewModel.recentEvents.isEmpty {
                                joinedEventsSection
                            }

                            Spacer(minLength: 24)
                        }
                        .frame(minHeight: proxy.size.height)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showEventCreation) {
                EventCreationSheet(
                    eventName: $eventName,
                    onCreate: {
                        Task {
                            await eventViewModel.createEvent(name: eventName.isEmpty ? "新しいイベント" : eventName)
                        }
                    }
                )
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView(eventViewModel: eventViewModel)
            }
            .fullScreenCover(isPresented: Binding(
                get: { eventRepository.currentEvent != nil },
                set: { _ in } // 閉じる導線はイベント終了／離脱のみで、いずれもリポジトリ側から起きる
            )) {
                // 作成直後は招待画面、参加直後はアルバム。
                // どちらに飛ばすかは EventViewModel.pendingTab が決める。
                // 撮影モードのときだけ、撮りたいシーンのタブを優先する
                // （通常起動・Releaseでは `initialTab` は常に nil）。
                MainTabView(initialTab: ScreenshotMode.initialTab ?? eventViewModel.pendingTab ?? .album)
            }
            // 失敗の理由を必ず画面に出す。以前は print だけだったので、
            // iCloud未サインインで作成に失敗しても何も起きないように見えていた。
            .alert("うまくいきませんでした",
                   isPresented: Binding(get: { eventViewModel.error != nil },
                                        set: { if !$0 { eventViewModel.error = nil } })) {
                Button("OK", role: .cancel) { eventViewModel.error = nil }
            } message: {
                Text(eventViewModel.error ?? "")
            }
            .overlay {
                if eventViewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                    }
                }
            }
        }
        .task {
            await eventViewModel.loadRecentEvents()
        }
        }
    }

    // MARK: - アプリタイトル

    private var titleSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(DesignTokens.primary)

            Text("EventSnap")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(DesignTokens.primary)

            Text("思い出を、みんなで")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - QRファインダー

    /// カメラファインダー風の大きな四角。QRコードで参加する導線を視覚的に
    /// 目立たせるための装飾で、タップ時の処理は`actionsSection`のQRスキャン
    /// ボタンと同じ`showQRScanner = true`を呼ぶだけ（QRScannerView自体は
    /// 一切変更しない）。既存のボタン・遷移ロジックはそのまま残す。
    ///
    /// 背景が白に戻ったため、枠自体をDesignTokens.primaryの濃い単色で塗り、
    /// 白背景に対してくっきり見えるコントラストを確保する
    /// （以前は白背景ベタ塗りに対して白い枠線を重ねる配色だったため、逆転させている）。
    private var qrFinderSection: some View {
        Button {
            showQRScanner = true
        } label: {
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusLarge, style: .continuous)
                .fill(DesignTokens.primary)
                .frame(width: 180, height: 180)
                .overlay {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(.white)
                }
                .shadow(color: DesignTokens.primary.opacity(0.3), radius: 10, y: 4)
        }
        .accessibilityLabel("QRコードで参加")
    }

    // MARK: - メインアクション

    private var actionsSection: some View {
        VStack(spacing: 20) {
            // イベント作成ボタン。白背景の上でくっきり見えるよう、
            // 共通のPrimaryButtonStyle（白背景+青文字。薄い背景の画面向け）ではなく、
            // DesignTokens.primaryの濃い単色塗りにする。
            Button {
                showEventCreation = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("新しいイベントを作成")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(DesignTokens.primary)
                .foregroundColor(.white)
                .cornerRadius(16)
            }

            // QRスキャンボタン（アウトライン、primaryカラー）
            Button {
                showQRScanner = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("QRコードで参加")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(DesignTokens.primary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DesignTokens.primary, lineWidth: 2)
                )
            }

            // 参加経路はQRコードだけ。その場に居合わせた人しか
            // 入れないことがEventSnapの前提なので、コードを
            // 伝えるだけで参加できる手段は用意しない。
            Text("参加できるのはQRコードを読み取った人だけです")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - 参加中のイベント

    /// 作成・参加したことのあるイベントへすぐ戻れる一覧。
    /// 終了済みのイベントもここから開ける（新しい写真は追加できない）。
    ///
    /// 「現在」と「過去」を分けて表示する。以前は「参加中のイベント」という
    /// 見出しの下に終了済みイベントまで並んでいて、見出しと中身が矛盾していた。
    private var joinedEventsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            let current = eventViewModel.recentEvents.filter(\.isActive)
            let past = eventViewModel.recentEvents.filter { !$0.isActive }

            if !current.isEmpty {
                eventGroup(title: "現在", events: current)
            }

            if !past.isEmpty {
                eventGroup(title: "過去のイベント", events: past)
            }
        }
        .padding(.horizontal, 40)
    }

    private func eventGroup(title: String, events: [Event]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(events) { event in
                    Button {
                        Task { await eventViewModel.switchEvent(to: event) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text("\(event.participantIDs.count)人")
                                    if !event.isActive {
                                        Text("終了")
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.18))
                                            .cornerRadius(4)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                    }
                }
            }
        }
    }
}

// MARK: - イベント作成シート

struct EventCreationSheet: View {
    @Binding var eventName: String
    @Environment(\.dismiss) var dismiss
    let onCreate: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                // HomeViewのブランドカラーを、ここでは主張しすぎない濃度で
                // 引き継ぐ。真っ白なシートが唐突に被さる違和感を無くすため。
                // DesignTokens統一に合わせ、二色グラデーションから単色ベースに変更。
                DesignTokens.primary.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("イベントを作成")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("イベント名を入力してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)

                    TextField("例: 文化祭2024", text: $eventName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    Button("作成する") {
                        onCreate()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationBarItems(trailing: Button("キャンセル") {
                dismiss()
            })
        }
    }
}

#Preview {
    HomeView()
}
