//
//  RelayCaptureChoiceView.swift
//  EventSnap
//
//  自分の番が開放されたときの投稿方法の選択
//

import SwiftUI

/// 「新規に撮影する」「今日のシェアOK写真から選ぶ」の2択。
/// 自分の番がまだ開放されていない人には、この画面自体（撮影導線）を一切見せない
/// （`RelayView`が`isMyTurnOpen`のときだけこのシートを開けるようにしている）。
struct RelayCaptureChoiceView: View {
    let onNewPhoto: () -> Void
    let onPickExisting: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Momentを投稿する")
                    .font(.headline)
                Text("どちらの方法で投稿しますか？")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            VStack(spacing: 14) {
                Button(action: onNewPhoto) {
                    ChoiceRow(
                        icon: "camera.fill",
                        title: "新規に撮影する",
                        subtitle: "その場でMomentを撮影します"
                    )
                }

                Button(action: onPickExisting) {
                    ChoiceRow(
                        icon: "photo.on.rectangle",
                        title: "今日のシェアOK写真から選ぶ",
                        subtitle: "今日撮ってシェアOKにした写真から1枚選びます"
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }
}

private struct ChoiceRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(DesignTokens.accentGradient)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusSmall, style: .continuous))
    }
}

#Preview {
    RelayCaptureChoiceView(onNewPhoto: {}, onPickExisting: {})
}
