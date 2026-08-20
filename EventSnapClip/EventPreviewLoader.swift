//
//  EventPreviewLoader.swift
//  EventSnapClip
//
//  CloudKitのPublic Databaseから、イベントと写真を読み取り専用で取得する。
//
//  メインアプリのServices/EventRepository.swift・Services/PhotoRepository.swiftは
//  あえて再利用していない。どちらも`ScreenshotMode.suppressesLiveServices`
//  （撮影モードの抑止）を経由しており、`ScreenshotMode`をApp Clipターゲットに
//  追加すると、DEBUGビルドでは`#if DEBUG`側の実装が`PreviewFixtureLoader`
//  （スクリーンショット用のFixture一式、画像アセットも含む）に依存するため、
//  App Clipには不要なコードと画像を大量に引き込んでしまう
//  （15MBのサイズ制限に対して無視できないリスクになる）。
//  加えて、`ScreenshotMode.isActive`は撮影後に元へ戻し忘れられたままの
//  ハードコード（`return true`）になっており、これを引き込むと
//  `suppressesLiveServices`が常にtrueになって、この読み込み自体が
//  常にno-opになってしまう問題もあった。
//
//  そのため、Event/Photoの読み取りに必要な最小限のロジックだけをここに
//  独立して実装する。書き込み系の処理は一切持たない。
//

import Foundation
import CloudKit

@MainActor
enum EventPreviewLoader {
    private static let database = CKContainer.default().publicCloudDatabase

    /// イベントIDから、そのイベントのレコードを取得する。
    /// メインアプリと同じ`event-{uuid}`recordIDでの直接取得（強い一貫性）を使う。
    /// 旧バージョンが作ったrecordNameがランダムなレコードへのフォールバックは、
    /// 新規にインストールされるApp Clipの用途では省略している。
    static func fetchEvent(id: UUID) async throws -> Event? {
        do {
            let record = try await database.record(for: Event.recordID(for: id))
            return Event.from(record: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// イベントの写真一覧（新しい順）を取得する。
    /// タイムカプセルでまだ公開されていない写真も含めてそのまま返す
    /// （公開判定はメインアプリと同じ`Photo.isRevealed`に委ねる。呼び出し側で絞り込む）。
    static func fetchPhotos(for eventID: UUID) async throws -> [Photo] {
        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Photo", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "uploadedAt", ascending: false)]

        let results = try await database.records(matching: query)

        var photos: [Photo] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(), let photo = Photo.from(record: record) {
                photos.append(photo)
            }
        }
        return photos
    }
}
