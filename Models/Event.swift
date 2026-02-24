//
//  Event.swift
//  EventSnap
//
//  イベントデータモデル
//

import Foundation
import CloudKit

struct Event: Identifiable, Codable {
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

    // CloudKitレコードへの変換
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: "Event")
        record["id"] = id.uuidString as CKRecordValue
        record["name"] = name as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["creatorID"] = creatorID as CKRecordValue
        record["participantIDs"] = participantIDs as CKRecordValue
        record["photoCount"] = photoCount as CKRecordValue
        record["isActive"] = (isActive ? 1 : 0) as CKRecordValue

        if let endedAt = endedAt {
            record["endedAt"] = endedAt as CKRecordValue
        }

        return record
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

        let endedAt = record["endedAt"] as? Date

        return Event(
            id: id,
            name: name,
            createdAt: createdAt,
            endedAt: endedAt,
            creatorID: creatorID,
            participantIDs: participantIDs,
            photoCount: photoCount,
            isActive: isActiveInt == 1
        )
    }
}
