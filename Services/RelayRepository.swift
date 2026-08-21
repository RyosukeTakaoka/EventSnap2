//
//  RelayRepository.swift
//  EventSnap
//
//  Relayデータ管理（CloudKit連携）
//

import Foundation
import CloudKit
import Combine

@MainActor
final class RelayRepository: ObservableObject {
    static let shared = RelayRepository()

    /// 現在表示中イベントのRelayセッション。存在しなければ`nil`（まだ始まっていない）。
    @Published var currentSession: RelaySession?
    @Published var isLoading = false
    @Published var error: Error?

    private let container = CKContainer.default()
    private var database: CKDatabase

    init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - 取得

    /// イベントに紐づくRelayセッションを取得する。まだ始まっていなければ`nil`を返す
    /// （存在しないこと自体はエラーではない）。
    ///
    /// 取得できた場合は必ず `expireStaleSlots` を適用してから返す。
    /// 「誰かがアプリを開いた／RelaySessionを取得した際に必ず期限切れの繰り上げ処理を行う」
    /// という仕様上の要である。ここを素通りさせると、silent pushを取りこぼした端末で
    /// いつまでも古い状態が表示され続けてしまう。
    @discardableResult
    func fetchSession(for eventID: UUID) async throws -> RelaySession? {
        guard let record = try await fetchRecord(eventID: eventID) else {
            currentSession = nil
            return nil
        }

        guard var session = RelaySession.from(record: record) else {
            currentSession = nil
            return nil
        }

        let before = session.slots
        session.expireStaleSlots()

        if session.slots != before {
            // 繰り上げが発生した＝状態が変わった。取得した端末がそのまま
            // 権威ある最新状態としてCloudKitへ書き戻す（次に開いた端末が
            // 毎回同じ計算をやり直しても、締切ベースの決定論的な値になるので
            // 複数端末が同時に書き戻しても結果は収束する）。
            do {
                try await save(session, existing: record)
            } catch {
                print("⚠️ Relay期限切れの繰り上げ保存に失敗（表示上は反映済み）: \(error)")
            }
        }

        currentSession = session
        return session
    }

    private func fetchRecord(eventID: UUID) async throws -> CKRecord? {
        do {
            return try await database.record(for: RelaySession.recordID(for: eventID))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - 開始

    /// Relayを開始する。既に開始済みの場合はそれをそのまま返す（二重開始しない）。
    @discardableResult
    func startRelay(event: Event, participantIDs: [String]) async throws -> RelaySession {
        isLoading = true
        defer { isLoading = false }

        if let existing = try await fetchSession(for: event.id) {
            return existing
        }

        try await CloudKitAccount.ensureAvailable()

        // イベント終了時刻の見込み。Eventは手動終了のみで自動終了しないため
        // 確定した終了時刻を持たないことが多い。あくまで表示用の見込み値とし、
        // 「新規追加できるか」の実際の判定は常にその場の`Event.isActive`を見る
        // （`RelayViewModel`参照）。
        let endsAt = event.endedAt ?? Date().addingTimeInterval(60 * 60 * 24)

        guard let session = RelaySession.start(eventID: event.id, participantIDs: participantIDs, endsAt: endsAt) else {
            throw RelayError.noParticipants
        }

        do {
            _ = try await database.save(session.toRecord())
            currentSession = session
            setupSubscription(for: event.id)
            print("✅ Relay開始成功: \(session.participantOrder.count)人")
            return session
        } catch {
            print("❌ Relay開始失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - 更新

    /// 撮影・選択が完了したときに呼ぶ。競合を避けるため、必ず最新レコードを
    /// 取り直してから上書きする（Event/Photoと同じ「取得済みレコードへの上書き」方式）。
    func completeSlot(eventID: UUID, participantID: String, photoID: UUID) async throws {
        guard let record = try await fetchRecord(eventID: eventID),
              var session = RelaySession.from(record: record)
        else {
            throw RelayError.notFound
        }

        session.expireStaleSlots()
        session.complete(participantID: participantID, photoID: photoID)

        try await save(session, existing: record)
        currentSession = session
    }

    private func save(_ session: RelaySession, existing record: CKRecord) async throws {
        _ = try await database.save(session.apply(to: record))
    }

    // MARK: - リアルタイム更新

    /// 前の人が撮影完了して前倒しでバトンが進んだことを全端末に知らせるための購読。
    /// `NotificationService`/`PhotoRepository.setupSubscription`と同じ設計
    /// （silent push → 受け取った端末がRelaySessionを取り直す）。
    ///
    /// RelaySessionは作成後も繰り返し更新される（完了・繰り上げのたび）ため、
    /// `firesOnRecordCreation`だけでなく`firesOnRecordUpdate`も必要になる点が
    /// Photoの購読（作成のみ）と異なる。
    func setupSubscription(for eventID: UUID) {
        guard !ScreenshotMode.suppressesLiveServices else { return }

        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let subscription = CKQuerySubscription(
            recordType: "RelaySession",
            predicate: predicate,
            subscriptionID: "relay-updated-\(eventID.uuidString)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        Task {
            do {
                _ = try await database.save(subscription)
                print("✅ Relayのリアルタイム同期設定完了")
            } catch {
                print("❌ Relay Subscription設定失敗: \(error)")
            }
        }
    }
}

enum RelayError: LocalizedError {
    case noParticipants
    case notFound

    var errorDescription: String? {
        switch self {
        case .noParticipants: return "参加者がいないためRelayを開始できません"
        case .notFound: return "Relayが見つかりません"
        }
    }
}
