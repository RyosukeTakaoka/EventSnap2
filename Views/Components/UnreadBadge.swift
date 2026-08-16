//
//  UnreadBadge.swift
//  EventSnap
//
//  LINEのような「未読件数」バッジ。Event Reelの新着通知に使う。
//

import SwiftUI

extension View {
    /// 右上に未読件数のバッジを重ねる。0件のときは何も表示しない。
    ///
    /// **なぜ `.offset` で外側にはみ出させないのか**: ツールバーのボタンに直接
    /// `.overlay` + `.offset` でバッジを付けると、ボタンの実測レイアウト範囲の
    /// 「外」にバッジが描画される。ナビゲーションバーのカスタムボタンは
    /// 実測範囲でクリップ・スナップショットされることがあり、その範囲外の
    /// 描画はクリップされて見えなくなったり（＝バッジが出ない）、
    /// 画面遷移のクロスフェード時に古いスナップショットが残ったり
    /// （＝一覧画面のバッジが個別画面に残って見える）する。
    ///
    /// そのためこの関数は「はみ出す」のではなく、**呼び出し側であらかじめ
    /// バッジの置き場を含む余裕のあるフレームを確保しておく**ことを前提にし、
    /// バッジ自体はそのフレームの内側（角ギリギリ）に収まる位置に置く。
    /// さらに遷移アニメーションでバッジ自体がクロスフェードして残像化しない
    /// よう、バッジの表示・非表示にはアニメーションを付けない。
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
                    // 親フレームの角のすぐ内側に収める(親がバッジの半分だけ余裕を
                    // 持った大きさになっている前提。過度にはみ出させない)。
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("未読\(count)件")
                    .transaction { $0.animation = nil }
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
