//
//  DeviceIdentity.swift
//  EventSnap
//
//  端末を識別するIDの発行と永続化
//

import Foundation
import UIKit

/// この端末を表すID。
///
/// 以前は各所で `UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString`
/// を直接呼んでいたが、これには2つの問題があった:
///
/// 1. `identifierForVendor` は端末の再起動直後やロック中に **nil を返すことがある**。
///    その場合フォールバックの `UUID()` が毎回別の値になり、同じ端末が別人として
///    扱われてイベントから追い出されていた（「毎回ログアウトさせられる」の主因）。
/// 2. 同じベンダーのアプリを全部消すと値が変わるため、再インストールで別人になる。
///
/// そこで **最初に決めたIDを UserDefaults に保存して以後ずっと使い回す**。
enum DeviceIdentity {
    private static let key = "deviceID"

    /// この端末の永続ID。初回アクセス時に発行して保存する。
    static let current: String = {
        let defaults = UserDefaults.standard

        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            return saved
        }

        // 初回のみ: identifierForVendor が取れればそれを使い、駄目なら新規UUID。
        // どちらにせよこの後は保存した値を使い続けるので、以降ブレることはない。
        let generated = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        defaults.set(generated, forKey: key)
        print("🆔 端末IDを新規発行しました: \(generated)")
        return generated
    }()

    private static let displayNameKey = "displayName"

    /// 表示用の端末名（「〇〇さんの新しい思い出」の〇〇に使う）
    static var displayName: String {
        let defaults = UserDefaults.standard
        if let custom = defaults.string(forKey: displayNameKey), !custom.isEmpty {
            return custom
        }
        return UIDevice.current.name
    }

    /// 本人が表示名を決めたことがあるか。
    ///
    /// これが `false` の間は `displayName` が端末名（「〇〇のiPhone」）を
    /// そのまま返しているだけの状態で、本人が選んだ名前ではない。
    /// イベントの作成・参加画面はこれを見て、初回だけ表示名の入力を求める。
    static var hasCustomDisplayName: Bool {
        !(UserDefaults.standard.string(forKey: displayNameKey) ?? "").isEmpty
    }

    static func setDisplayName(_ name: String) {
        UserDefaults.standard.set(name, forKey: displayNameKey)
    }
}
