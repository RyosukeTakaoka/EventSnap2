//
//  EventSnapClipView.swift
//  EventSnapClip
//
//  App Clipのメインビュー
//

import SwiftUI
import StoreKit

struct EventSnapClipView: View {
    @EnvironmentObject var eventViewModel: EventViewModel
    @State private var showingAppStoreOverlay = false

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                // アプリアイコン & タイトル
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 70))
                        .foregroundColor(.white)

                    Text("EventSnap")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("イベントの思い出を共有")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.top, 60)

                Spacer()

                // メインコンテンツ
                if eventViewModel.isLoading {
                    // ローディング中
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("イベントに参加しています...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                } else if eventViewModel.hasJoinedEvent {
                    // 参加成功
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)

                        Text("イベントに参加しました！")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if let event = eventViewModel.currentEvent {
                            Text(event.name)
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal)
                        }

                        // フルアプリのダウンロードを促す
                        VStack(spacing: 16) {
                            Text("完全版アプリをダウンロードして\nすべての機能を楽しもう")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.9))

                            Button {
                                showingAppStoreOverlay = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.app.fill")
                                    Text("アプリをダウンロード")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.blue)
                                .cornerRadius(16)
                            }
                            .padding(.horizontal, 40)
                        }
                        .padding(.top, 20)

                        // カメラへ移動ボタン（App Clip内で使用可能）
                        NavigationLink(destination: CameraView()) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("写真を撮影する")
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
                        .padding(.horizontal, 40)
                    }
                } else {
                    // エラーまたは待機中
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)

                        Text(eventViewModel.error ?? "QRコードからアクセスしてください")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button {
                            showingAppStoreOverlay = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.app.fill")
                                Text("完全版アプリをダウンロード")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(.blue)
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 40)
                    }
                }

                Spacer()

                // App Clipバッジ
                HStack {
                    Image(systemName: "app.badge")
                    Text("App Clip")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 20)
            }
        }
        .appStoreOverlay(isPresented: $showingAppStoreOverlay) {
            // App Store ID を指定（実際のApp Store IDに置き換えてください）
            SKOverlay.AppConfiguration(appIdentifier: "YOUR_APP_STORE_ID", position: .bottom)
        }
    }
}

#Preview {
    NavigationView {
        EventSnapClipView()
            .environmentObject(EventViewModel())
    }
}
