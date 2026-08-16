//
//  UnreadBadge.swift
//  EventSnap
//
//  LINEのような「未読件数」バッジ。Event Reelの新着通知に使う。
//

import SwiftUI

extension View {
    /// 右上に未読件数のバッジを重ねる。0件のときは何も表示しない。
    @ViewBuilder
    func unreadBadge(_ count: Int) -> some View {
        overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, count > 9 ? 5 : 0)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Color.red, in: Capsule())
                    .overlay(Capsule().stroke(Color(.systemBackground), lineWidth: 1.5))
                    .offset(x: 10, y: -10)
                    .accessibilityLabel("未読\(count)件")
            }
        }
    }
}

/// Listの行の中などインライン表示で使う小さな数字バッジ。
/// (overlayだと行の高さに埋もれてしまうため、リスト行には専用の見た目を用意している)
struct InlineUnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.red, in: Capsule())
        }
    }
}
