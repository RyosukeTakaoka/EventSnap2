//
//  HomeView.swift
//  EventSnap
//
//  ホーム画面
//

import SwiftUI

struct HomeView: View {
    @StateObject private var eventViewModel = EventViewModel()
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

                VStack(spacing: 40) {
                    Spacer()

                    // アプリタイトル
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

                    Spacer()

                    // メインアクション
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
                    }
                    .padding(.horizontal, 40)

                    Spacer()
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
            .fullScreenCover(isPresented: $eventViewModel.hasJoinedEvent) {
                MainTabView()
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
