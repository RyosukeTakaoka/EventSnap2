//
//  InviteCode.swift
//  EventSnap
//
//  離れた相手にも口頭・テキストで伝えられる招待コード
//

import Foundation

/// 6文字の招待コード。
///
/// QRコードはその場にいる人にしか使えないので、遠くにいる人を誘えるように
/// 短いコードでも参加できるようにする。
///
/// 読み違い・打ち間違いを避けるため、紛らわしい文字は使わない:
///   - `0` と `O`、`1` と `I` と `L` を除外
///   - 入力は大文字小文字を区別しない（`normalize` で吸収する）
enum InviteCode {
    /// 紛らわしい文字を抜いた32文字のアルファベット
    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    static let length = 6

    /// 新しい招待コードを生成する
    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// ユーザー入力を照合可能な形に整える。
    /// 空白・ハイフンを除去し、大文字化し、間違えやすい文字を寄せる。
    static func normalize(_ raw: String) -> String {
        var s = raw.uppercased()
        s.removeAll { $0 == " " || $0 == "-" || $0 == "　" }

        // ユーザーが 0/O, 1/I/L を打ってしまった場合の救済
        s = s.replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "I")
        // O→なし, I→なし なので、さらに近い有効文字へ寄せる
        s = s.replacingOccurrences(of: "O", with: "Q")
            .replacingOccurrences(of: "I", with: "J")
            .replacingOccurrences(of: "L", with: "J")

        return s
    }

    /// 見た目の整形（`ABC-DEF` の形にして読み上げやすくする）
    static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        let mid = code.index(code.startIndex, offsetBy: length / 2)
        return "\(code[code.startIndex..<mid])-\(code[mid...])"
    }

    /// 入力が招待コードとして成立しているか
    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }
}
