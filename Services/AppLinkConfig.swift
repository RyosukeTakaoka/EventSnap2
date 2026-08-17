//
//  AppLinkConfig.swift
//  EventSnap
//
//  QRコードに埋め込むURLの設定
//

import Foundation

/// QRコード／App Clip で使うURLの組み立て。
///
/// ## ⚠️ 出荷前に必ず直すこと
///
/// `host` が `eventsnap.example.com` のままだと、**アプリ内のスキャナ以外からは
/// 参加できません**。`example.com` は誰も所有できない予約済みドメインです。
///
/// 具体的には次が起きます。
///
/// - 標準の「カメラ」アプリでQRを読むと Safari が開き、行き先が無くて終わる
///   （多くの人はこちらで読もうとするので「読み取れない」と言われる）
/// - App Clip が起動しない
/// - Universal Link が開かない
///
/// アプリ内のスキャナ（`QRScannerView`）はURLから文字列としてIDを取り出すので
/// 動きますが、それは「アプリを入れている人同士」でしか使えません。
///
/// ## 直す手順
///
/// 1. 自分のドメインを用意する（例: `eventsnap.app`）
/// 2. 下の `host` をそのドメインに変える
/// 3. `EventSnap.entitlements` の `com.apple.developer.associated-domains` に
///    **`applinks:` と `appclips:` を追加する**
///    （現在は `webcredentials:example.com` だけで、`applinks:` が無いため
///    そもそもUniversal Linkとして機能しない）
///
///    ```xml
///    <array>
///        <string>applinks:eventsnap.app</string>
///        <string>appclips:eventsnap.app</string>
///    </array>
///    ```
///
/// 4. `https://eventsnap.app/.well-known/apple-app-site-association` を
///    Content-Type `application/json` で配信する
enum AppLinkConfig {

    /// QRコードの行き先になるドメイン
    static let host = "eventsnap-website.vercel.app"
    /// このドメインが実在するものに差し替わっているか。
    /// 予約済みドメインのままなら、アプリ外からの参加は成立しない。
    static var isConfigured: Bool {
        !host.hasSuffix("example.com")
    }

    /// イベント参加用のURL
    static func joinURL(eventID: UUID) -> String {
        "https://\(host)/event/\(eventID.uuidString)"
    }
}
