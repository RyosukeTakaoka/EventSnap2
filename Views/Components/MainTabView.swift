//
//  MainTabView.swift
//  EventSnap
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var eventViewModel = EventViewModel()

    /// 最初に開くタブ。既定は最もよく見るアルバム。
    var initialTab: AppTab = .album

    @State private var selectedTab: AppTab = .album
    @State private var showEventSwitcher = false

    var body: some View {
        TabView(selection: $selectedTab) {
            AlbumView(eventViewModel: eventViewModel, showEventSwitcher: $showEventSwitcher)
                .tabItem { Label(AppTab.album.title, systemImage: AppTab.album.icon) }
                .tag(AppTab.album)

            CameraView()
                .tabItem { Label(AppTab.camera.title, systemImage: AppTab.camera.icon) }
                .tag(AppTab.camera)

            QRCodeView(eventViewModel: eventViewModel)
                .tabItem { Label(AppTab.invite.title, systemImage: AppTab.invite.icon) }
                .tag(AppTab.invite)

            EventSettingsView(eventViewModel: eventViewModel, showEventSwitcher: $showEventSwitcher)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
        }
        .accentColor(.blue)
        .sheet(isPresented: $showEventSwitcher) {
            EventSwitcherView(eventViewModel: eventViewModel)
        }
        // Widgetをタップして開いたEvent Reelを、その場でシェアできる画面として直接開く。
        // 設定タブ→「Event Reelを見る」まで潜らせると「見る→シェアする」の
        // 導線が長くなってしまうため、Widgetからの入場だけはショートカットする。
        .sheet(isPresented: Binding(
            get: { eventViewModel.pendingReelID != nil },
            set: { isPresented in if !isPresented { eventViewModel.pendingReelID = nil } }
        )) {
            if let event = eventViewModel.currentEvent,
               let reelID = eventViewModel.pendingReelID,
               let reel = ShareCollageStore.shared.reels(for: event.id).first(where: { $0.id == reelID }) {
                NavigationView {
                    SocialCardShareView(event: event, reel: reel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { eventViewModel.pendingReelID = nil }
                            }
                        }
                }
            }
        }
        .onAppear {
            selectedTab = initialTab
        }
        // イベントを作った直後は招待画面、参加した直後はアルバムへ飛ばす
        .onReceive(eventViewModel.$pendingTab.compactMap { $0 }) { tab in
            selectedTab = tab
            eventViewModel.pendingTab = nil
        }
        .task {
            // MainTabViewはHomeView側でcurrentEventがある時にしか提示されないため、
            // ここでイベントが無い場合の自動作成は行わない。
            //
            // 以前はここで「イベントが無ければデフォルトイベントを作る」という
            // 保険を入れていたが、これが原因でイベント終了時にバグっていた:
            // 終了処理でcurrentEventがnilになった瞬間にこの保険が発火し、
            // 新しい「マイイベント」を勝手に作ってMainTabViewに居座ってしまい、
            // タイトル画面に戻ったように見えなくなっていた。
            await NotificationService.shared.requestAuthorization()
        }
    }
}

// MARK: - イベント設定ビュー

struct EventSettingsView: View {
    @ObservedObject var eventViewModel: EventViewModel
    @Binding var showEventSwitcher: Bool

    @StateObject private var collageStore = ShareCollageStore.shared
    @State private var showEndConfirmation = false
    @State private var displayName = DeviceIdentity.displayName

    var body: some View {
        NavigationView {
            List {
                Section("イベント情報") {
                    LabeledRow(title: "イベント名",
                               value: eventViewModel.currentEvent?.name ?? "読み込み中...")

                    LabeledRow(title: "参加者",
                               value: "\(eventViewModel.participants.count)人")

                    if let createdAt = eventViewModel.currentEvent?.createdAt {
                        LabeledRow(title: "作成日時",
                                   value: createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section {
                    Button {
                        showEventSwitcher = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("イベントを切り替える")
                            Spacer()
                            Text("\(eventViewModel.recentEvents.count)件")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("グループ")
                } footer: {
                    Text("参加したことのあるイベントを行き来できます。切り替えても、それぞれのアルバムはそのまま残ります。")
                }

                Section("表示名") {
                    TextField("あなたの表示名", text: $displayName)
                        .onSubmit { DeviceIdentity.setDisplayName(displayName) }
                    Text("タイムカプセルの通知で「〇〇さんの新しい思い出」と表示されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Event Reel") {
                    if let event = eventViewModel.currentEvent,
                       collageStore.hasAnyReel(for: event.id) {
                        NavigationLink {
                            ShareCollageView(event: event)
                        } label: {
                            HStack {
                                Label("Event Reelを見る", systemImage: "square.and.arrow.up.on.square")
                                Spacer()
                                InlineUnreadBadge(count: collageStore.unseenReelCount(for: event.id))
                            }
                        }
                    } else {
                        Text("撮影時に「シェアOK」を選んだ写真は、その場で自動的にEvent Reelになります。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showEndConfirmation = true
                    } label: {
                        Label("イベントを終了", systemImage: "xmark.circle")
                    }
                } header: {
                    Text("危険な操作")
                } footer: {
                    Text("イベントを終了すると、新しい写真の追加ができなくなります。旅行や合宿など複数日にまたがるイベントでは、日付が変わっても自動では終了しません。")
                }
            }
            .navigationTitle("設定")
            // confirmationDialog はボトムシートで、スクロール位置によって
            // 出てくる場所が画面内でずれて見えることがあるため、
            // 常に画面中央に出る alert に変更している。
            .alert("このイベントを終了しますか？", isPresented: $showEndConfirmation) {
                Button("終了する", role: .destructive) {
                    Task { await eventViewModel.endEvent() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("新しい写真の追加ができなくなります。")
            }
        }
    }
}

// MARK: - 小物

struct LabeledRow: View {
    let title: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .modifier(MonospacedIfNeeded(enabled: monospaced))
        }
    }
}

private struct MonospacedIfNeeded: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.font(.system(.body, design: .monospaced))
        } else {
            content
        }
    }
}

#Preview {
    MainTabView()
}
