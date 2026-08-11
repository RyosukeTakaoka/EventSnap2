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
        NavigationView {
            ZStack {
                // 背景グラデーション
                LinearGradient(
                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 32) {
                            Spacer(minLength: 24)

                            titleSection

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
                MainTabView(initialTab: eventViewModel.pendingTab ?? .album)
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

    // MARK: - アプリタイトル

    private var titleSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.white)

            Text("EventSnap")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("思い出を、みんなで")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
    }

    // MARK: - メインアクション

    private var actionsSection: some View {
        VStack(spacing: 20) {
            // イベント作成ボタン
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
                .background(Color.white)
                .foregroundColor(.blue)
                .cornerRadius(16)
            }

            // QRスキャンボタン
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
                .background(Color.white.opacity(0.2))
                .foregroundColor(.white)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: 2)
                )
            }

            // 参加経路はQRコードだけ。その場に居合わせた人しか
            // 入れないことがEventSnapの前提なので、コードを
            // 伝えるだけで参加できる手段は用意しない。
            Text("参加できるのはQRコードを読み取った人だけです")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - 参加中のイベント

    /// 作成・参加したことのあるイベントへすぐ戻れる一覧。
    /// 終了済みのイベントもここから開ける（新しい写真は追加できない）。
    private var joinedEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("参加中のイベント")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.85))

            VStack(spacing: 8) {
                ForEach(eventViewModel.recentEvents) { event in
                    Button {
                        Task { await eventViewModel.switchEvent(to: event) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text("\(event.participantIDs.count)人")
                                    if !event.isActive {
                                        Text("終了")
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.white.opacity(0.25))
                                            .cornerRadius(4)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.75))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(14)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - イベント作成シート

struct EventCreationSheet: View {
    @Binding var eventName: String
    @Environment(\.dismiss) var dismiss
    let onCreate: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("イベント名を入力")
                    .font(.title2)
                    .fontWeight(.bold)

                TextField("例: 文化祭2024", text: $eventName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button("作成してQRコードを表示") {
                    onCreate()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("キャンセル") {
                dismiss()
            })
        }
    }
}

#Preview {
    HomeView()
}
