//
//  RelayCompletionView.swift
//  EventSnap
//
//  Relayの完成イメージ（埋まっている分だけの作品）画面
//

import SwiftUI

/// 埋まった分だけをグリッドで表示する完成画面。
///
/// 空欄のマスは「失敗」を思わせる表現（赤色・×マーク・「未撮影」等）を使わず、
/// 「◯◯さんのMomentを待っています」という前向きな文言＋控えめなプレースホルダーで示す。
/// イベント終了時点で埋まっている分だけを使って作品を確定する、という仕様どおり、
/// この画面はいつ開いても「今埋まっている分」をそのまま見せる（別途「確定」操作は無い）。
struct RelayCompletionView: View {
    let session: RelaySession
    let rows: [RelayParticipantRow]

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(rows) { row in
                        RelayCompletionCell(row: row)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Relayの完成イメージ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 4) {
            let filled = rows.filter { $0.slot.status == .completed }.count
            Text("\(filled) / \(rows.count) 人のMomentが埋まっています")
                .font(.subheadline.weight(.semibold))
            Text("埋まっている分だけで作品になります。空欄は失敗ではありません。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct RelayCompletionCell: View {
    let row: RelayParticipantRow

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            switch row.slot.status {
            case .completed:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .clipped()
            case .open, .waiting:
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall, style: .continuous))
        .task {
            guard let photoID = row.slot.photoID,
                  let photo = PhotoRepository.shared.allPhotos.first(where: { $0.id == photoID })
            else { return }
            image = await PhotoImageLoader.shared.thumbnail(for: photo)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.6))
            Text("\(row.participant.deviceName)さんの\nMomentを待っています")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.tertiarySystemBackground))
    }
}

#Preview {
    NavigationView {
        RelayCompletionView(
            session: RelaySession.start(eventID: UUID(), participantIDs: ["a", "b", "c"], endsAt: Date())!,
            rows: []
        )
    }
}
