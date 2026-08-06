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
        apply(to: CKRecord(recordType: "Event"))
    }

    // CloudKitレコードからの変換
    static func from(record: CKRecord) -> Event? {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = record["name"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let creatorID = record["creatorID"] as? String,
            let participantIDs = record["participantIDs"] as? [String],
            let photoCount = record["photoCount"] as? Int,
            let isActiveInt = record["isActive"] as? Int
        else {
            return nil
        }

        return Event(
            id: id,
            name: name,
            createdAt: createdAt,
            endedAt: record["endedAt"] as? Date,
            creatorID: creatorID,
            participantIDs: participantIDs,
            photoCount: photoCount,
            isActive: isActiveInt == 1
        )
    }
}
