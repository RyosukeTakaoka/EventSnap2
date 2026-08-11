//
//  CloudKitAccount.swift
//  EventSnap
//
//  iCloudアカウントの状態確認
//

import Foundation
import CloudKit

/// iCloudにサインインしているかを確認する。
///
/// ## なぜ必要か
///
/// EventSnapは CloudKit の **Public Database** にイベントと写真を保存している。
/// 読み取りは誰でもできるが、**書き込みには iCloud へのサインインが必須**
/// （Security Role の Write が `Authenticated` のため）。
///
/// この確認をしていないと、iCloudにサインインしていない端末では:
///
/// - イベントを作ろうとすると `.notAuthenticated` で失敗 →「部屋が作れない」
/// - QRを読んで参加しようとしても参加者リストの更新に失敗 →「部屋に入れない」
///
/// となるうえ、画面には理由の分からない失敗としか出ないため、
/// 原因が分からないまま詰まってしまう。
///
/// 開発中の端末はたいていiCloudにサインイン済みなので**テストでは再現せず、
/// 実機で他の人に使ってもらうと失敗する**、という形で表面化する。
enum CloudKitAccount {

    /// 書き込みができる状態かを確認する。
    /// 問題があれば、そのまま画面に出せる日本語のエラーを投げる。
    static func ensureAvailable() async throws {
        let status: CKAccountStatus
        do {
            status = try await CKContainer.default().accountStatus()
        } catch {
            print("❌ iCloudアカウントの確認に失敗: \(error)")
            throw CloudKitAccountError.statusUnavailable
        }

        switch status {
        case .available:
            return
        case .noAccount:
            throw CloudKitAccountError.noAccount
        case .restricted:
            throw CloudKitAccountError.restricted
        case .couldNotDetermine:
            throw CloudKitAccountError.statusUnavailable
        case .temporarilyUnavailable:
            throw CloudKitAccountError.temporarilyUnavailable
        @unknown default:
            throw CloudKitAccountError.statusUnavailable
        }
    }

    /// 確認だけしたい場合（UIの出し分け用）
    static var isAvailable: Bool {
        get async {
            (try? await CKContainer.default().accountStatus()) == .available
        }
    }
}

enum CloudKitAccountError: LocalizedError {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case statusUnavailable

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "iCloudにサインインしていません。\n「設定」アプリからサインインしてください。"
        case .restricted:
            return "この端末ではiCloudの利用が制限されています。\n機能制限の設定をご確認ください。"
        case .temporarilyUnavailable:
            return "iCloudに一時的に接続できません。\nしばらくしてからもう一度お試しください。"
        case .statusUnavailable:
            return "iCloudの状態を確認できませんでした。\nネットワーク接続をご確認ください。"
        }
    }
}
