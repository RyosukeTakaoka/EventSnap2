//
//  Photo.swift
//  EventSnap
//
//  写真データモデル
//

import Foundation
import CloudKit

struct Photo: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let eventID: UUID
    let uploaderID: String
    /// 通知文言（「〇〇さんの新しい思い出が公開されました」）に使う表示名
    var uploaderName: String?
    let uploadedAt: Date
    var imageURL: URL?
    var thumbnailURL: URL?
    var filterName: String?
    var aiProcessed: Bool

    // MARK: - タイムカプセル（機能A）

    /// 遅延公開の対象か
    var isTimeCapsule: Bool
    /// 公開予定日時。`isTimeCapsule == true` のときだけ意味を持つ
    var revealDate: Date?

    // MARK: - シェアコラージュ（機能B）

    /// 撮影者が「この写真はSNSでシェアしてよい」と明示的に許可したか。
    /// **デフォルトは false**。本人がONにした写真だけがコラージュに使われる。
    var isShareOK: Bool

    init(
        id: UUID = UUID(),
        eventID: UUID,
        uploaderID: String,
        uploaderName: String? = nil,
        uploadedAt: Date = Date(),
        imageURL: URL? = nil,
        thumbnailURL: URL? = nil,
        filterName: String? = nil,
        aiProcessed: Bool = false,
        isTimeCapsule: Bool = false,
        revealDate: Date? = nil,
        isShareOK: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.uploaderID = uploaderID
        self.uploaderName = uploaderName
        self.uploadedAt = uploadedAt
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.filterName = filterName
        self.aiProcessed = aiProcessed
        self.isTimeCapsule = isTimeCapsule
        self.revealDate = revealDate
        self.isShareOK = isShareOK
    }

    // MARK: - 公開判定

    /// 公開済みか。
    ///
    /// `isRevealed` を別フィールドとして持たず **`revealDate <= 現在時刻` で判定する**。
    /// CloudKitには「指定時刻にサーバー側でフラグを立てる」仕組みが無いため、
    /// フラグを持つと誰かがアプリを開いて書き換えるまで false のままになってしまい、
    /// 端末ごとに見え方がズレる。日時比較なら全端末で同じ結果になる。
    func isRevealed(asOf now: Date = Date()) -> Bool {
        guard isTimeCapsule, let revealDate else { return true }
        return revealDate <= now
    }

    /// 指定の端末から見えるべき写真か。
    /// 未公開のタイムカプセル写真は、撮影者本人にだけ見えるようにする。
    func isVisible(to deviceID: String, asOf now: Date = Date()) -> Bool {
        isRevealed(asOf: now) || uploaderID == deviceID
    }

    /// 公開までのおおよその残り日数（正確な日時は見せない方針）
    func daysUntilReveal(asOf now: Date = Date()) -> Int? {
        guard isTimeCapsule, let revealDate, revealDate > now else { return nil }
        let seconds = revealDate.timeIntervalSince(now)
        return max(1, Int(ceil(seconds / 86_400)))
    }

    /// タイムカプセル状態を解除して通常公開の写真にする。
    ///
    /// シェアOKとタイムカプセルが重複したときに使う。
    /// 「未来の再訪価値より、イベント終了直後の共有価値を優先する」という判断。
    func releasedFromTimeCapsule() -> Photo {
        var released = self
        released.isTimeCapsule = false
        released.revealDate = nil
        return released
    }

    // MARK: - CloudKit

    /// レコードIDを写真のUUIDから決める（Eventと同じ理由）。
    /// クエリは結果整合なので、保存直後に確実に取り出すには recordID が要る。
    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "photo-\(id.uuidString)")
    }

    var recordID: CKRecord.ID { Self.recordID(for: id) }

    /// 既存レコードへの書き込み。
    /// 新規 `CKRecord` を作り直すと recordID が変わって複製になるため、
    /// 更新時は取得済みのレコードを渡すこと。
    @discardableResult
    func apply(to record: CKRecord) -> CKRecord {
        record["id"] = id.uuidString as CKRecordValue
        record["eventID"] = eventID.uuidString as CKRecordValue
        record["uploaderID"] = uploaderID as CKRecordValue
        record["uploadedAt"] = uploadedAt as CKRecordValue
        record["aiProcessed"] = (aiProcessed ? 1 : 0) as CKRecordValue
        record["isTimeCapsule"] = (isTimeCapsule ? 1 : 0) as CKRecordValue
        record["isShareOK"] = (isShareOK ? 1 : 0) as CKRecordValue
        record["filterName"] = filterName as CKRecordValue?
        record["uploaderName"] = uploaderName as CKRecordValue?
        // 解除時に nil を入れて消せるよう、条件分岐せず常に代入する
        record["revealDate"] = revealDate as CKRecordValue?
        return record
    }

    func toRecord() -> CKRecord {
        apply(to: CKRecord(recordType: "Photo", recordID: recordID))
    }

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
        let uploaderName = record["uploaderName"] as? String

        // v1のレコードには存在しないフィールド。無い場合は
        // 「タイムカプセルではない = 即時公開」「シェア不可」として扱う。
        // これにより既存の写真はこれまでと全く同じ挙動になる。
        let isTimeCapsule = (record["isTimeCapsule"] as? Int ?? 0) == 1
        let isShareOK = (record["isShareOK"] as? Int ?? 0) == 1
        let revealDate = record["revealDate"] as? Date

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
            uploaderName: uploaderName,
            uploadedAt: uploadedAt,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            filterName: filterName,
            aiProcessed: aiProcessedInt == 1,
            isTimeCapsule: isTimeCapsule,
            revealDate: revealDate,
            isShareOK: isShareOK
        )
    }
}
