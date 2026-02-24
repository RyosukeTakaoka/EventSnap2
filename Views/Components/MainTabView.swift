//
//  MainTabView.swift
//  EventSnap
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var eventViewModel = EventViewModel()
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            QRCodeView(eventViewModel: eventViewModel)
                .tabItem {
                    Label("QRコード", systemImage: "qrcode")
                }
                .tag(0)

            CameraView()
                .tabItem {
                    Label("カメラ", systemImage: "camera.fill")
                }
                .tag(1)

            AlbumView()
                .tabItem {
                    Label("アルバム", systemImage: "photo.on.rectangle")
                }
                .tag(2)

            EventSettingsView(eventViewModel: eventViewModel)
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
                .tag(3)
        }
        .accentColor(.blue)
        .task {
            // アプリ起動時にイベントがなければ作成
            if eventViewModel.currentEvent == nil {
                print("⚠️ イベントがないため、デフォルトイベントを作成します")
                await eventViewModel.createEvent(name: "マイイベント")
            }
        }
    }
}

// MARK: - イベント設定ビュー

struct EventSettingsView: View {
    @ObservedObject var eventViewModel: EventViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("イベント情報") {
                    HStack {
                        Text("イベント名")
                        Spacer()
                        Text(eventViewModel.currentEvent?.name ?? "読み込み中...")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("参加者")
                        Spacer()
                        Text("\(eventViewModel.participants.count)人")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("作成日時")
                        Spacer()
                        if let createdAt = eventViewModel.currentEvent?.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("アクション") {
                    Button {
                        Task {
                            await eventViewModel.refreshEvent()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("更新")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await eventViewModel.endEvent()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("イベントを終了")
                        }
                    }
                } header: {
                    Text("危険な操作")
                } footer: {
                    Text("イベントを終了すると、新しい写真の追加ができなくなります。")
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    MainTabView()
}
