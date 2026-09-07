//
//  Reaction.swift
//  EventSnap
//
//  写真への絵文字リアクション
//
//  InstagramやYouTubeの「いいね」のような、**数字が可視化されて競争になる**
//  仕組みは意図的に避ける。出すのは「どの絵文字を、誰が押したか」だけで、
//  件数は集計も表示もしない（`ReactionRepository`参照）。
//
//  1人が同じ写真に **何種類でも** 押せる（Messengerのリアクションに近い）。
//  「1人1個」に絞ると、複数の気持ちが重なったときに選び直す形になり、
//  結局どれか1つを選ばせる＝いいねの延長になってしまうため。
//

import Foundation
import CloudKit

struct Reaction: Identifiable, Codable, Equatable, Hashable {
    let eventID: UUID
    let photoID: UUID
    /// リアクションした人の端末ID（`DeviceIdentity.current`）。
    /// 同じ人の同じ絵文字を二重に作らないための識別に使う。
    let reactorID: String
    /// 表示用の名前。押した時点の`DeviceIdentity.displayName`を焼き込む。
    /// `Photo.uploaderName`と同じ考え方で、後から名前を変えても
    /// 当時の表示が壊れないようにレコード側に持たせている。
    var reactorName: String?
    let emoji: String
    let createdAt: Date

    static let availableEmojis = ["❤️", "😂", "😮", "👏", "🎉"]

    /// 画面に出す名前。未設定の古いレコード向けのフォールバック付き。
    var displayName: String {
        if let reactorName, !reactorName.isEmpty { return reactorName }
        return reactorID == DeviceIdentity.current ? DeviceIdentity.displayName : "参加者"
    }

    // MARK: - Identifiable用

    var id: String { "\(photoID.uuidString)-\(reactorID)-\(Self.slug(for: emoji))" }

    // MARK: - CloudKit

    /// 絵文字をrecordNameに使える形（ASCII）へ変換する。
    ///
    /// `CKRecord.ID`のrecordNameには **ASCII文字しか使えない** ため、絵文字を
    /// そのまま埋め込むことはできない。Unicodeスカラー値を16進で並べた文字列
    /// （❤️なら`2764-fe0f`）にしておけば、絵文字の種類を後から増やしても
    /// 対応表を書き足さずに一意なIDが作れる。
    static func slug(for emoji: String) -> String {
        emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }

    /// recordIDを (photoID, reactorID, 絵文字) から決める。
    ///
    /// **絵文字までIDに含めるのが重要**。同じ人が同じ写真に複数の絵文字を
    /// 押せる仕様なので、絵文字ごとに別レコードにしないと押すたびに
    /// 上書きし合ってしまう。この形なら、1つ押す/外す操作が他の絵文字の
    /// レコードに一切触れないため、複数人が同時に押しても衝突しない
    /// （Event/Photoの`recordID`固定と同じ考え方）。
    static func recordID(for photoID: UUID, reactorID: String, emoji: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "reaction-\(photoID.uuidString)-\(reactorID)-\(slug(for: emoji))")
    }

    var recordID: CKRecord.ID { Self.recordID(for: photoID, reactorID: reactorID, emoji: emoji) }

    @discardableResult
    func apply(to record: CKRecord) -> CKRecord {
        record["eventID"] = eventID.uuidString as CKRecordValue
        record["photoID"] = photoID.uuidString as CKRecordValue
        record["reactorID"] = reactorID as CKRecordValue
        record["reactorName"] = reactorName as CKRecordValue?
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

        return Reaction(
            eventID: eventID,
            photoID: photoID,
            reactorID: reactorID,
            reactorName: record["reactorName"] as? String,
            emoji: emoji,
            createdAt: createdAt
        )
    }
}
