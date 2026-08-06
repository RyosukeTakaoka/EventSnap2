//
//  AppTab.swift
//  EventSnap
//
//  タブの並び順の一元管理
//

import Foundation

/// メイン画面のタブ。
///
/// 以前は `selectedTab = 0` のような数値を各所に直接書いていたため、
/// 並び順を変えるたびに全ての箇所を直す必要があった。enum に集約して
/// 並び替えを `allCases` の順序だけで済むようにする。
///
/// 並びはユーザーテストのフィードバックに合わせて **最もよく見るアルバムを左端**に置く。
enum AppTab: Int, CaseIterable, Identifiable {
    case album      // 一番よく開くので左端
    case camera     // 中心となる操作
    case timeCapsule // イベント後に再訪してもらうための枠
    case invite     // QR・招待コード
    case settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .album:       return "アルバム"
        case .camera:      return "カメラ"
        case .timeCapsule: return "カプセル"
        case .invite:      return "招待"
        case .settings:    return "設定"
        }
    }

    var icon: String {
        switch self {
        case .album:       return "photo.on.rectangle"
        case .camera:      return "camera.fill"
        case .timeCapsule: return "hourglass"
        case .invite:      return "qrcode"
        case .settings:    return "gear"
        }
    }
}
