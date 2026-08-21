//
//  RelayPhotoPickerView.swift
//  EventSnap
//
//  今日のシェアOK写真からRelayに投稿する1枚を選ぶ画面
//

import SwiftUI

/// `AlbumView`のグリッド表示パターン（`LazyVGrid` + 正方形セル）を踏襲する。
/// 対象は「自分が撮影し、当日撮影かつシェアOKにした写真」のみ
/// （他の参加者が代理で撮ることは今回実装しない）。
struct RelayPhotoPickerView: View {
    @ObservedObject var viewModel: RelayViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isSubmitting = false
    @State private var selectedPhotoID: UUID?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            Group {
                let photos = viewModel.todaysOwnShareOKPhotos
                if photos.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(photos) { photo in
                                RelayPickerCell(photo: photo, isSelected: photo.id == selectedPhotoID)
                                    .onTapGesture { selectedPhotoID = photo.id }
                            }
                        }
                    }
                }
            }
            .navigationTitle("今日のシェアOK写真")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("この写真にする")
                        }
                    }
                    .disabled(selectedPhotoID == nil || isSubmitting)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("今日のシェアOK写真がありません")
                .font(.headline)
            Text("撮影時に「シェアOK」をONにした、今日撮影分の写真だけが選べます。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard let id = selectedPhotoID,
              let photo = viewModel.todaysOwnShareOKPhotos.first(where: { $0.id == id })
        else { return }

        Task {
            isSubmitting = true
            let success = await viewModel.submitExistingPhoto(photo)
            isSubmitting = false
            if success { dismiss() }
        }
    }
}

private struct RelayPickerCell: View {
    let photo: Photo
    let isSelected: Bool

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DesignTokens.primary, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, DesignTokens.primary)
                        .padding(6)
                }
            }
            .task {
                image = await PhotoImageLoader.shared.thumbnail(for: photo)
            }
    }
}

#Preview {
    RelayPhotoPickerView(viewModel: RelayViewModel())
}
