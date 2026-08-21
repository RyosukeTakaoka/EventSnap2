//
//  RelaySession.swift
//  EventSnap
//
//  Relay（バトン形式の共同アルバム）のセッション状態
//

import Foundation
import CloudKit

/// Relayの参加者1人分の枠。
///
/// `status`の遷移は `waiting → open → completed` の一方向のみで、後戻りしない。
/// `open`になった枠は、本人が撮り終える（`completed`になる）まで**ずっと**
/// 撮影可能なままにする（締切ではない）。優先時間は「次の人を待たせないための
/// 解放トリガー」に過ぎず、本人の撮影権を奪うものではない。
struct RelaySlot: Codable, Equatable {
    enum Status: String, Codable {
        case waiting
        case open
        case completed
    }

    let participantID: String
    var status: Status
    var photoID: UUID?
    /// この枠が開放された時刻。`waiting`のときは`nil`。
    var openedAt: Date?
}

/// イベント参加者がランダムな順番で「主役」になり、順にMomentを撮影してつなげていく
/// 共同アルバム機能（Relay）の1セッション分。
///
/// ## 設計方針: 「失敗にならない」バトン
///
/// BeRealのような強制感（締切に間に合わなければ失敗）を避け、Setlogのような
/// 「間に合わなくても失敗にならない」を核心にする。そのため:
///
/// - `participantOrder`（誰の後に誰が来るか）は開始時に確定し、以後変わらない
/// - `priorityWindowSeconds`（優先時間）が過ぎても、その人の枠は閉じない。
///   ただの「次の人を待たせないための解放トリガー」であり、締切ではない
/// - 前の人が優先時間内に撮り終えれば、待たずに即座に次の人が開放される（前倒し）
/// - イベント終了時点で埋まっている分だけを使って作品を確定する。空欄は失敗ではなく「まだ」
///
/// ## 1イベント1Relay
///
/// `recordID`を`eventID`から決め打ちにしている（Event/Photoと同じ理由: 強い一貫性で
/// 直後に取得できるようにするため）。副作用として**1つのイベントにつきRelayは1回だけ**
/// という制約になるが、「その回のRelay」という仕様の書きぶりとも合致するシンプルな設計。
struct RelaySession: Identifiable, Codable, Equatable {
    let id: UUID
    let eventID: UUID
    /// 参加者IDのランダム順配列。Relay開始時にシャッフルして固定する（以後変わらない）。
    let participantOrder: [String]
    /// `participantOrder`と同じ並び順の状態配列。
    var slots: [RelaySlot]
    let priorityWindowSeconds: Int
    let startedAt: Date
    /// イベント終了時刻の見込み。**実際のゲーティングには使わない**
    /// （新規追加できるかどうかは常にその場の`Event.isActive`を見る。Eventは日付が変わっても
    /// 自動終了しないため、ここでの見込み時刻はあくまで参考値・表示用）。
    var endsAt: Date

    init(
        id: UUID = UUID(),
        eventID: UUID,
        participantOrder: [String],
        slots: [RelaySlot],
        priorityWindowSeconds: Int,
        startedAt: Date = Date(),
        endsAt: Date
    ) {
        self.id = id
        self.eventID = eventID
        self.participantOrder = participantOrder
        self.slots = slots
        self.priorityWindowSeconds = priorityWindowSeconds
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    // MARK: - 優先時間（人数に応じて可変）

    /// 参加人数に応じた優先時間（秒）。
    /// 2〜3人: 15分 / 4〜5人: 10分 / 6〜8人: 7分 / 9〜20人: 5分。
    /// 範囲外（1人以下・21人以上）は安全側（それぞれ最長・最短）に丸める。
    static func priorityWindowSeconds(forParticipantCount count: Int) -> Int {
        switch count {
        case ..<4: return 15 * 60
        case 4...5: return 10 * 60
        case 6...8: return 7 * 60
        default: return 5 * 60
        }
    }

    // MARK: - 開始

    /// 参加者リストをランダムにシャッフルして新規セッションを作る。
    /// 最初の1人（`participantOrder[0]`）は開始と同時に`open`になる。
    static func start(eventID: UUID, participantIDs: [String], endsAt: Date, now: Date = Date()) -> RelaySession? {
        guard !participantIDs.isEmpty else { return nil }

        let order = participantIDs.shuffled()
        var slots = order.map { RelaySlot(participantID: $0, status: .waiting, photoID: nil, openedAt: nil) }
        slots[0].status = .open
        slots[0].openedAt = now

        return RelaySession(
            eventID: eventID,
            participantOrder: order,
            slots: slots,
            priorityWindowSeconds: priorityWindowSeconds(forParticipantCount: order.count),
            startedAt: now,
            endsAt: endsAt
        )
    }

    // MARK: - バトンの進み方

    /// 指定した参加者が撮影・選択を完了したときに呼ぶ。
    ///
    /// 本人の枠を`completed`にし、**優先時間を待たず即座に**次の`waiting`の枠を
    /// 開放する（前倒し）。次の枠が既に`open`（優先時間切れで先に開放済み）だった
    /// 場合は何もしない（既に開いているので前倒しの必要が無い）。
    mutating func complete(participantID: String, photoID: UUID, now: Date = Date()) {
        guard let index = slots.firstIndex(where: { $0.participantID == participantID }) else { return }
        guard slots[index].status != .completed else { return }

        slots[index].status = .completed
        slots[index].photoID = photoID
        // 開放時刻(openedAt)は変えない。「いつ主役になったか」の記録として残す。

        let nextIndex = index + 1
        guard nextIndex < slots.count, slots[nextIndex].status == .waiting else { return }
        slots[nextIndex].status = .open
        slots[nextIndex].openedAt = now
    }

    /// 期限切れによる繰り上げ。誰かがアプリを開いた際・RelaySessionを取得した際に必ず呼ぶ。
    ///
    /// **サーバー側の厳密な監視はしない**。現在時刻と「直前の枠が開いた時刻＋優先時間」を
    /// 比較し、過ぎていれば次の`waiting`枠を開放する。この判定を先頭から順に連鎖させることで、
    /// 長時間誰もアプリを開かなかった場合でも、開いた瞬間にまとめて追いつく。
    ///
    /// 開放時刻には`now`ではなく「計算上の締切（前の枠のopenedAt + 優先時間）」を使う。
    /// これにより、どの端末が・いつこの関数を呼んでも結果が同じになる
    /// （`now`を使うと、呼んだ端末・タイミングによって`openedAt`がズレて、
    /// 参加者ごとにバトンの進み方が違って見えてしまう）。
    ///
    /// 既に`open`・`completed`の枠は変更しない（後戻りしない）。
    mutating func expireStaleSlots(now: Date = Date()) {
        guard var cursor = slots.first?.openedAt else { return }

        for index in 1..<slots.count {
            guard slots[index].status == .waiting else {
                // 既に開いている枠は、その実際の開放時刻を次の締切計算の起点にする
                // （前倒しで早く開いていれば、その分次の締切も早まる）。
                cursor = slots[index].openedAt ?? cursor
                continue
            }

            let deadline = cursor.addingTimeInterval(TimeInterval(priorityWindowSeconds))
            guard now >= deadline else { break } // これより先の枠は、まだ開けない

            slots[index].status = .open
            slots[index].openedAt = deadline
            cursor = deadline
        }
    }

    // MARK: - 予測（通知の事前予約用）

    /// 「今後、何も操作されなかった場合」に指定した参加者の枠が開くと見込まれる時刻。
    /// 既に`open`/`completed`ならその実際の`openedAt`を返す。
    ///
    /// 通知は「予定時刻に事前予約」する必要があるため、`expireStaleSlots`のように
    /// `now`で判定を打ち切らず、未来方向にも計算を進める。前の人が早く撮り終えれば
    /// 実際にはもっと早く開くが、その場合はsilent push経由で通知を前倒し発火させる
    /// （`RelayNotificationService`）。
    func predictedOpenDate(forParticipantID participantID: String) -> Date? {
        guard let targetIndex = slots.firstIndex(where: { $0.participantID == participantID }) else { return nil }
        if let opened = slots[targetIndex].openedAt { return opened }

        guard var cursor = slots.first?.openedAt else { return nil }
        for index in 1...targetIndex {
            if let opened = slots[index].openedAt {
                cursor = opened
            } else {
                cursor = cursor.addingTimeInterval(TimeInterval(priorityWindowSeconds))
            }
        }
        return cursor
    }

    // MARK: - 状態の参照

    var isFinished: Bool {
        slots.allSatisfy { $0.status == .completed }
    }

    func slot(for participantID: String) -> RelaySlot? {
        slots.first { $0.participantID == participantID }
    }

    /// 完成画面用: 埋まっている枠だけを撮影順(=バトンの順番)で返す
    var completedSlots: [RelaySlot] {
        slots.filter { $0.status == .completed }
    }

    // MARK: - CloudKit

    static func recordID(for eventID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "relay-\(eventID.uuidString)")
    }

    var recordID: CKRecord.ID { Self.recordID(for: eventID) }

    /// slotsは可変長の構造体配列のため、CloudKitのネイティブ型に対応が無い。
    /// Photo/Eventが単純なスカラー値の列挙なのに対し、Relayだけ構造を持つため
    /// JSON文字列にエンコードしてStringフィールドとして保存する（仕様が明示的に指定した方式）。
    @discardableResult
    func apply(to record: CKRecord) -> CKRecord {
        record["id"] = id.uuidString as CKRecordValue
        record["eventID"] = eventID.uuidString as CKRecordValue
        record["participantOrder"] = participantOrder as CKRecordValue
        record["priorityWindowSeconds"] = priorityWindowSeconds as CKRecordValue
        record["startedAt"] = startedAt as CKRecordValue
        record["endsAt"] = endsAt as CKRecordValue

        if let slotsJSON = try? JSONEncoder().encode(slots),
           let slotsString = String(data: slotsJSON, encoding: .utf8) {
            record["slotsJSON"] = slotsString as CKRecordValue
        }

        return record
    }

    func toRecord() -> CKRecord {
        apply(to: CKRecord(recordType: "RelaySession", recordID: recordID))
    }

    static func from(record: CKRecord) -> RelaySession? {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let eventIDString = record["eventID"] as? String,
            let eventID = UUID(uuidString: eventIDString),
            let participantOrder = record["participantOrder"] as? [String],
            let priorityWindowSeconds = record["priorityWindowSeconds"] as? Int,
            let startedAt = record["startedAt"] as? Date,
            let endsAt = record["endsAt"] as? Date,
            let slotsString = record["slotsJSON"] as? String,
            let slotsData = slotsString.data(using: .utf8),
            let slots = try? JSONDecoder().decode([RelaySlot].self, from: slotsData)
        else {
            return nil
        }

        return RelaySession(
            id: id,
            eventID: eventID,
            participantOrder: participantOrder,
            slots: slots,
            priorityWindowSeconds: priorityWindowSeconds,
            startedAt: startedAt,
            endsAt: endsAt
        )
    }
}
