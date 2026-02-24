//
//  AlbumView.swift
//  EventSnap
//
//  アルバム画面
//

import SwiftUI

struct AlbumView: View {
    @StateObject private var viewModel = AlbumViewModel()
    @StateObject private var eventViewModel = EventViewModel()

    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if viewModel.photos.isEmpty {
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
                    // 写真グリッド
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(viewModel.photos) { photo in
                            NavigationLink(destination: PhotoDetailView(photo: photo, viewModel: viewModel)) {
                                PhotoCell(photo: photo, viewModel: viewModel) // ViewModelを渡す
                            }
                        }
                    }
                }
            }
            .navigationTitle("アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Label("\(viewModel.photos.count)枚", systemImage: "photo.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .refreshable {
                await viewModel.fetchPhotos()
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
            .clipped()
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

                // 写真情報
                VStack(spacing: 8) {
                    Text("撮影日時: \(photo.uploadedAt.formatted())")
                        .font(.caption)
                        .foregroundColor(.white)

                    if let filterName = photo.filterName {
                        Text("フィルター: \(filterName)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    saveImageToPhotos()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.white)
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

#Preview {
    AlbumView()
}
