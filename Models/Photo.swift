//
//  Photo.swift
//  EventSnap
//
//  写真データモデル
//

import Foundation
import CloudKit

struct Photo: Identifiable, Codable {
    let id: UUID
    let eventID: UUID
    let uploaderID: String
    let uploadedAt: Date
    var imageURL: URL?
    var thumbnailURL: URL?
    var filterName: String?
    var aiProcessed: Bool

    init(
        id: UUID = UUID(),
        eventID: UUID,
        uploaderID: String,
        uploadedAt: Date = Date(),
        imageURL: URL? = nil,
        thumbnailURL: URL? = nil,
        filterName: String? = nil,
        aiProcessed: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.uploaderID = uploaderID
        self.uploadedAt = uploadedAt
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.filterName = filterName
        self.aiProcessed = aiProcessed
    }

    // CloudKitレコードへの変換
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: "Photo")
        record["id"] = id.uuidString as CKRecordValue
        record["eventID"] = eventID.uuidString as CKRecordValue
        record["uploaderID"] = uploaderID as CKRecordValue
        record["uploadedAt"] = uploadedAt as CKRecordValue
        record["aiProcessed"] = (aiProcessed ? 1 : 0) as CKRecordValue

        if let filterName = filterName {
            record["filterName"] = filterName as CKRecordValue
        }

        return record
    }

    // CloudKitレコードからの変換
    static func from(record: CKRecord) -> Photo? {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let eventIDString = record["eventID"] as? String,
            let eventID = UUID(uuidString: eventIDString),
            let uploaderID = record["uploaderID"] as? String,
            let uploadedAt = record["uploadedAt"] as? Date,
            let aiProcessedInt = record["aiProcessed"] as? Int
        else {
            return nil
        }

        let filterName = record["filterName"] as? String

        // CKAssetからURLを取得
        var imageURL: URL?
        var thumbnailURL: URL?

        if let imageAsset = record["imageAsset"] as? CKAsset {
            imageURL = imageAsset.fileURL
        }

        if let thumbnailAsset = record["thumbnailAsset"] as? CKAsset {
            thumbnailURL = thumbnailAsset.fileURL
        }

        return Photo(
            id: id,
            eventID: eventID,
            uploaderID: uploaderID,
            uploadedAt: uploadedAt,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            filterName: filterName,
            aiProcessed: aiProcessedInt == 1
        )
    }
}
