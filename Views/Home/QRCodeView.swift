//
//  QRCodeView.swift
//  EventSnap
//
//  QRコード表示画面
//

import SwiftUI

struct QRCodeView: View {
    @ObservedObject var eventViewModel: EventViewModel // 外部から受け取る
    @State private var qrCodeImage: UIImage?
    @State private var isGenerating = true
    @State private var generationFailed = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 30) {
            Text("友達を招待")
                .font(.title)
                .fontWeight(.bold)

            Text("このQRコードを読み取ってもらおう！")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // QRコード表示エリア
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .frame(width: 280, height: 280)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                // 状態に応じた表示
                if isGenerating {
                    // 生成中の表示
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("QRコード生成中...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let image = qrCodeImage {
                    // QRコード表示
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .transition(.opacity)
                } else if generationFailed {
                    // エラー表示
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("QRコードの生成に\n失敗しました")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        // エラーメッセージ表示
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            generateQRCode()
                        }) {
                            Text("再試行")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .frame(width: 280, height: 280)
            .animation(.easeInOut(duration: 0.3), value: isGenerating)
            .animation(.easeInOut(duration: 0.3), value: qrCodeImage != nil)

            // イベント情報
            VStack(spacing: 12) {
                Text(eventViewModel.currentEvent?.name ?? "イベント名なし")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 20) {
                    Label("\(eventViewModel.participants.count)人", systemImage: "person.2.fill")
                    Label("\(eventViewModel.currentEvent?.photoCount ?? 0)枚", systemImage: "photo.fill")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                // デバッグ情報（開発中のみ表示）
                #if DEBUG
                Text("イベントID: \(eventViewModel.currentEvent?.id.uuidString ?? "なし")")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                #endif
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)

            Spacer()
        }
        .padding()
        .onAppear {
            debugEventViewModel()
            generateQRCode()
        }
    }

    /// EventViewModelの状態をデバッグ
    private func debugEventViewModel() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 EventViewModel デバッグ情報")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        if let event = eventViewModel.currentEvent {
            print("✅ currentEventが存在します")
            print("  - イベント名: \(event.name)")
            print("  - イベントID: \(event.id.uuidString)")
            print("  - 写真枚数: \(event.photoCount)")
        } else {
            print("❌ currentEventがnilです！")
            print("⚠️ イベントが作成されていないか、読み込まれていない可能性があります")
        }
        
        print("\n📊 その他の情報")
        print("  - 参加者数: \(eventViewModel.participants.count)")
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }

    /// QRコードを非同期で生成
    private func generateQRCode() {
        // 状態をリセット
        isGenerating = true
        generationFailed = false
        qrCodeImage = nil
        errorMessage = ""

        print("🎬 QRコード生成を開始します")

        // currentEventの存在確認
        guard let currentEvent = eventViewModel.currentEvent else {
            print("❌ エラー: eventViewModel.currentEventがnilです")
            errorMessage = "イベントが見つかりません"
            isGenerating = false
            generationFailed = true
            return
        }

        let eventID = currentEvent.id.uuidString
        print("📋 イベントID: \(eventID)")

        // App Clip URLを生成（本番環境では実際のドメインに変更してください）
        // 開発中は "eventsnap.example.com" を使用
        // 実際には、自分で管理するドメインを使用する必要があります
        let appClipURL = "https://eventsnap.example.com/event/\(eventID)"
        print("🔗 App Clip URL: \(appClipURL)")

        // 非同期でQRコード生成（App Clip URLを使用）
        QRCodeService.generateQRCode(from: appClipURL) { image in
            if let image = image {
                print("✅ QRコード生成成功！")
                self.qrCodeImage = image
                self.isGenerating = false
                self.generationFailed = false
            } else {
                print("❌ QRコード生成失敗")
                self.errorMessage = "QRコード画像の生成に失敗しました"
                self.qrCodeImage = nil
                self.isGenerating = false
                self.generationFailed = true
            }
        }
    }
}

// プレビュー用
#Preview {
    // プレビュー用のダミーEventViewModelを作成
    let viewModel = EventViewModel()
    return QRCodeView(eventViewModel: viewModel)
}
