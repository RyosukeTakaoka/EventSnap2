//
//  Reaction.swift
//  EventSnap
//
//  写真への絵文字リアクション
//
//  InstagramやYouTubeの「いいね」のような、数字が可視化されて競争っぽくなる
//  仕組みは意図的に避ける。誰が押したかも見せず、写真の隅に絵文字が
//  並ぶだけに留める（`ReactionRepository.emojiSummary`参照）。
//  「押した/押していない」の二値ではなく、いくつかの絵文字から
//  気持ちに近いものを選べるようにすることで、いいね数のような単一指標の
//  競争にならないようにしている。
//

import Foundation
import CloudKit

struct Reaction: Identifiable, Codable, Equatable, Hashable {
    let eventID: UUID
    let photoID: UUID
    /// リアクションした人の端末ID（`DeviceIdentity.current`）。
    /// 表示はしない。1人1枚の写真につき最新の1個だけを保持するための識別に使う。
    let reactorID: String
    var emoji: String
    let createdAt: Date

    static let availableEmojis = ["❤️", "😂", "😮", "👏", "🎉"]

    // MARK: - Identifiable用

    /// 「1人が1枚の写真に持てるリアクションは常に1個」という制約をIDにも
    /// 反映しておく（同じ人が同じ写真に複数のリアクションを持つことはない）。
    var id: String { "\(photoID.uuidString)-\(reactorID)" }

    // MARK: - CloudKit

    /// recordIDを (photoID, reactorID) から決める。
    ///
    /// こうしておくと「同じ人が同じ写真に付け直す」操作が、常に同じレコードへの
    /// 上書きになる。ランダムなrecordIDだと、絵文字を変えるたびに新しいレコードが
    /// 増えてしまい、「1人1個」を保つために毎回まず既存レコードを検索する必要が
    /// 出てしまう（Event/Photoの`recordID`と同じ考え方）。
    static func recordID(for photoID: UUID, reactorID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "reaction-\(photoID.uuidString)-\(reactorID)")
    }

    var recordID: CKRecord.ID { Self.recordID(for: photoID, reactorID: reactorID) }

    @discardableResult
    func apply(to record: CKRecord) -> CKRecord {
        record["eventID"] = eventID.uuidString as CKRecordValue
        record["photoID"] = photoID.uuidString as CKRecordValue
        record["reactorID"] = reactorID as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        return record
    }

    func toRecord() -> CKRecord {
        apply(to: CKRecord(recordType: "Reaction", recordID: recordID))
    }

    static func from(record: CKRecord) -> Reaction? {
        guard
            let eventIDString = record["eventID"] as? String,
            let eventID = UUID(uuidString: eventIDString),
            let photoIDString = record["photoID"] as? String,
            let photoID = UUID(uuidString: photoIDString),
            let reactorID = record["reactorID"] as? String,
            let emoji = record["emoji"] as? String,
            let createdAt = record["createdAt"] as? Date
        else {
            return nil
        }

        return Reaction(eventID: eventID, photoID: photoID, reactorID: reactorID, emoji: emoji, createdAt: createdAt)
    }
}
