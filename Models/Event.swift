//
//  Event.swift
//  EventSnap
//
//  イベントデータモデル
//

import Foundation
import CloudKit

struct Event: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var endedAt: Date?
    let creatorID: String
    var participantIDs: [String]
    var photoCount: Int
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        endedAt: Date? = nil,
        creatorID: String,
        participantIDs: [String] = [],
        photoCount: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.creatorID = creatorID
        self.participantIDs = participantIDs
        self.photoCount = photoCount
        self.isActive = isActive
    }

    // MARK: - CloudKit

    /// レコードIDをイベントのUUIDから決める。
    ///
    /// こうしておくと `CKDatabase.record(for:)` で **直接** 取得できる。
    /// クエリ（`records(matching:)`）はインデックス経由で結果整合なので、
    /// 保存した直後のレコードは数秒〜数十秒ヒットしないことがある。
    /// 「イベントを作った直後にQRを読んでも参加できない」の原因がこれ。
    /// recordID での取得だけが強い一貫性を持つ。
    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "event-\(id.uuidString)")
    }

    var recordID: CKRecord.ID { Self.recordID(for: id) }

    /// 既存のレコードに値を書き込む。
    ///
    /// 毎回 `CKRecord(recordType:)` で新規レコードを作ると **recordID が新しく振られて
    /// 別レコードになってしまう**（＝更新のつもりが複製になる）。
    /// 更新時は取得済みのレコードを渡して、同じ recordID のまま上書きする。
    @discardableResult
    func apply(to record: CKRecord) -> CKRecord {
        record["id"] = id.uuidString as CKRecordValue
        record["name"] = name as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["creatorID"] = creatorID as CKRecordValue
        record["participantIDs"] = participantIDs as CKRecordValue
        record["photoCount"] = photoCount as CKRecordValue
        record["isActive"] = (isActive ? 1 : 0) as CKRecordValue
        record["endedAt"] = endedAt as CKRecordValue?
        return record
    }

    /// 新規作成用
    func toRecord() -> CKRecord {
        apply(to: CKRecord(recordType: "Event", recordID: recordID))
    }

    /// recordName（`event-<UUID>`）からイベントIDを取り出す。
    /// `id` フィールドが欠けているレコードでも、これで身元が分かる。
    static func eventID(fromRecordName recordName: String) -> UUID? {
        guard recordName.hasPrefix("event-") else { return nil }
        return UUID(uuidString: String(recordName.dropFirst("event-".count)))
    }

    /// CloudKitレコードからの変換。
    ///
    /// ## なぜ「1つでも欠けたらnil」を止めたのか
    ///
    /// 以前は8つのフィールドすべてを `guard let` で必須にしていた。
    /// この形だと、CloudKit側のフィールドが1つでも欠けている・型が違うだけで
    /// **レコードは存在するのに `nil`** が返り、呼び出し側からは
    /// 「イベントが存在しない」と見分けが付かなかった。
    ///
    /// 実際にはこうなる状況が普通にありうる。
    ///
    /// - Production環境へスキーマをDeployし忘れていて、一部のフィールドが無い
    /// - 旧バージョンが作ったレコードに新しいフィールドが入っていない
    /// - Dashboardでフィールドの型を後から変えた
    ///
    /// このとき利用者には「参加できません／イベントが見つかりません」としか
    /// 出ず、しかも `EventRepository.loadRecentEvents` が「見つからない＝消えた」
    /// と解釈して **参加履歴からグループを消してしまっていた**。
    ///
    /// そこで、身元を決める **イベントIDだけ**を必須にし（`id` フィールドが
    /// 無くても recordName から復元する）、残りは既定値で補って読み込む。
    /// 補った箇所はログに残すので、スキーマの不備は開発時に気付ける。
    static func from(record: CKRecord) -> Event? {
        let idFromField = (record["id"] as? String).flatMap(UUID.init(uuidString:))

        guard let id = idFromField ?? Self.eventID(fromRecordName: record.recordID.recordName) else {
            print("⚠️ Eventレコードを読めません（IDを特定できない）: \(record.recordID.recordName)")
            return nil
        }

        let name = record["name"] as? String
        let createdAt = record["createdAt"] as? Date
        let creatorID = record["creatorID"] as? String
        let participantIDs = record["participantIDs"] as? [String]
        let photoCount = record["photoCount"] as? Int
        let isActiveInt = record["isActive"] as? Int

        let checks: [(String, Bool)] = [
            ("name", name == nil),
            ("createdAt", createdAt == nil),
            ("creatorID", creatorID == nil),
            ("participantIDs", participantIDs == nil),
            ("photoCount", photoCount == nil),
            ("isActive", isActiveInt == nil)
        ]
        let missing = checks.filter { $0.1 }.map { $0.0 }

        if !missing.isEmpty {
            print("""
            ⚠️ Eventレコードに欠けているフィールドがあります: \(missing.joined(separator: ", "))
               recordName: \(record.recordID.recordName)
               CloudKit Console のスキーマ（特に Production 環境）を確認してください。
               既定値で補って読み込みます。
            """)
        }

        return Event(
            id: id,
            name: name ?? "イベント",
            // createdAt が無ければ、CloudKitが必ず持っているレコード作成日時で代用する
            createdAt: createdAt ?? record.creationDate ?? Date(),
            endedAt: record["endedAt"] as? Date,
            creatorID: creatorID ?? "",
            participantIDs: participantIDs ?? [],
            photoCount: photoCount ?? 0,
            // isActive が無いレコードは、終了日時が入っていなければ開催中とみなす
            isActive: isActiveInt.map { $0 == 1 } ?? (record["endedAt"] as? Date == nil)
        )
    }
}
