//
//  EventRepository.swift
//  EventSnap
//
//  イベントデータ管理（CloudKit連携）
//

import Foundation
import CloudKit
import Combine
import UIKit

@MainActor
class EventRepository: ObservableObject {
    static let shared = EventRepository()

    @Published var currentEvent: Event?
    @Published var participants: [Participant] = []
    /// 過去に作成・参加したイベント（最近使った順）。グループ切り替えに使う。
    @Published var recentEvents: [Event] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let container = CKContainer.default()
    private var database: CKDatabase

    private let currentEventIDKey = "currentEventID"
    private let joinedEventIDsKey = "joinedEventIDs"

    /// 履歴に残す上限
    private let historyLimit = 20

    init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - 永続化

    private var savedCurrentEventID: String? {
        UserDefaults.standard.string(forKey: currentEventIDKey)
    }

    private func saveCurrentEventID(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: currentEventIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentEventIDKey)
        }
    }

    /// 参加履歴。先頭ほど最近使ったもの。
    private var joinedEventIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: joinedEventIDsKey) ?? [] }
        set {
            UserDefaults.standard.set(Array(newValue.prefix(historyLimit)), forKey: joinedEventIDsKey)
        }
    }

    private func rememberEvent(_ id: UUID) {
        var ids = joinedEventIDs
        ids.removeAll { $0 == id.uuidString }
        ids.insert(id.uuidString, at: 0)
        joinedEventIDs = ids
    }

    private func forgetEvent(_ id: UUID) {
        joinedEventIDs = joinedEventIDs.filter { $0 != id.uuidString }
    }

    // MARK: - 起動時の復元

    /// 前回開いていたイベントを復元する。
    ///
    /// 参加処理を走らせ直すと participantIDs を毎回書き換えてしまうので、
    /// 復元は **読み取りのみ** で行う。
    func restoreEvent() async {
        // 撮影モードでは復元しない（注入済みのFixtureを維持する）
        guard !ScreenshotMode.suppressesLiveServices else { return }

        guard currentEvent == nil, let savedID = savedCurrentEventID else { return }

        do {
            guard let event = try await fetchEvent(id: savedID) else {
                print("⚠️ 保存されていたイベントが見つかりません。履歴から削除します")
                if let uuid = UUID(uuidString: savedID) { forgetEvent(uuid) }
                saveCurrentEventID(nil)
                return
            }
            applyCurrent(event)
            print("✅ イベントを復元しました: \(event.name)")
        } catch {
            // 通信エラーの場合は保存を消さない。次回の起動でまた試す。
            print("⚠️ イベントの復元に失敗（保存は維持）: \(error)")
        }

        await loadRecentEvents()
    }

    // MARK: - イベント作成

    /// 新規イベントを作成
    func createEvent(name: String) async throws -> Event {
        isLoading = true
        defer { isLoading = false }

        // 書き込みには iCloud へのサインインが要る。
        // 先に確認しておかないと、原因の分からない失敗になる。
        try await CloudKitAccount.ensureAvailable()

        let deviceID = DeviceIdentity.current

        let event = Event(
            name: name,
            creatorID: deviceID,
            participantIDs: [deviceID]
        )

        do {
            _ = try await database.save(event.toRecord())
            applyCurrent(event)
            rememberEvent(event.id)
            await loadRecentEvents()

            print("✅ イベント作成成功: \(event.id)")
            return event
        } catch {
            print("❌ イベント作成失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - イベント参加

    /// イベントIDで参加する。
    ///
    /// 参加経路は **QRコードの読み取り（およびApp Clip / Universal Link）だけ**。
    /// 「その場に居合わせた人だけが入れる」というEventSnapの前提を守るため、
    /// 文字列を伝えるだけで入れる招待コードのような経路は用意しない。
    func joinEvent(eventID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard UUID(uuidString: eventID) != nil else {
            throw EventError.invalidID
        }

        // 参加者リストへの書き込みが発生するので、先にiCloudを確認する
        try await CloudKitAccount.ensureAvailable()

        guard let event = try await fetchEvent(id: eventID) else {
            throw EventError.notFound
        }

        var updated = event
        let deviceID = DeviceIdentity.current

        if !updated.participantIDs.contains(deviceID) {
            updated.participantIDs.append(deviceID)
            do {
                try await save(updated)
            } catch {
                print("❌ 参加者リストの更新に失敗: \(error)")
                self.error = error
                throw error
            }
        }

        applyCurrent(updated)
        rememberEvent(updated.id)
        await loadRecentEvents()

        print("✅ イベント参加成功: \(updated.name)")
    }

    // MARK: - グループ切り替え

    /// 参加済みイベントを読み込む（切り替え画面用）
    func loadRecentEvents() async {
        // 撮影モードでは履歴を読み直さない（注入済みのFixtureを維持する）
        guard !ScreenshotMode.suppressesLiveServices else { return }

        let ids = joinedEventIDs
        guard !ids.isEmpty else {
            recentEvents = []
            return
        }

        var loaded: [Event] = []
        var missing: [String] = []

        for id in ids {
            do {
                if let event = try await fetchEvent(id: id) {
                    loaded.append(event)
                } else {
                    missing.append(id)
                }
            } catch {
                print("⚠️ 履歴イベントの取得に失敗: \(id)")
            }
        }

        if !missing.isEmpty {
            joinedEventIDs = joinedEventIDs.filter { !missing.contains($0) }
        }

        recentEvents = loaded
    }

    /// 別のイベントに切り替える。
    /// すでに参加済みなので、参加者リストへの書き込みは行わない。
    func switchEvent(to event: Event) async {
        guard event.id != currentEvent?.id else { return }

        applyCurrent(event)
        rememberEvent(event.id)

        if let fresh = try? await fetchEvent(id: event.id.uuidString) {
            applyCurrent(fresh)
        }

        await loadRecentEvents()
        print("🔀 イベントを切り替えました: \(event.name)")
    }

    /// 履歴から外す（CloudKit上のイベントは消さない）
    func leaveEvent(_ event: Event) async {
        forgetEvent(event.id)
        await NotificationService.shared.cancelReveals(for: event.id)
        RelayNotificationService.shared.cancelAll(for: event.id, participantIDs: event.participantIDs)

        if currentEvent?.id == event.id {
            saveCurrentEventID(nil)
            currentEvent = nil
            participants = []
        }

        await loadRecentEvents()

        if currentEvent == nil, let next = recentEvents.first {
            await switchEvent(to: next)
        }
    }

    // MARK: - イベント取得

    private func fetchEvent(id: String) async throws -> Event? {
        try await fetchRecord(id: id).flatMap(Event.from(record:))
    }

    /// イベントのレコードを取得する。
    ///
    /// ## なぜ2段構えなのか
    ///
    /// CloudKit のクエリ（`records(matching:)`）は **結果整合**で、
    /// 保存した直後のレコードはインデックスに載るまで数秒〜数十秒ヒットしない。
    /// クエリだけに頼ると、**イベントを作った直後にQRを読ませても
    /// 「イベントが見つかりません」**になる。開発中は作ってから試すまでに
    /// 間が空くので再現しにくく、その場で読ませる実際の使い方でだけ失敗する。
    ///
    /// `record(for:)` による recordID 直接取得は **強い一貫性**を持つので、
    /// 保存した次の瞬間でも必ず取れる。まずこちらを試す。
    private func fetchRecord(id: String) async throws -> CKRecord? {
        guard let uuid = UUID(uuidString: id) else { return nil }

        // ① recordID で直接取得（強い一貫性）
        do {
            return try await database.record(for: Event.recordID(for: uuid))
        } catch let error as CKError where error.code == .unknownItem {
            // このIDのレコードは無い。旧形式の可能性があるので②へ。
        } catch {
            throw error
        }

        // ② 旧バージョンが作ったレコードは recordName がランダムなので
        //    フィールド検索でしか見つけられない
        let predicate = NSPredicate(format: "id == %@", id)
        let query = CKQuery(recordType: "Event", predicate: predicate)
        let results = try await database.records(matching: query)

        guard let (_, result) = results.matchResults.first else { return nil }
        return try? result.get()
    }

    /// イベントを保存する（既存があれば上書き、無ければ新規作成）
    private func save(_ event: Event) async throws {
        if let existing = try await fetchRecord(id: event.id.uuidString) {
            _ = try await database.save(event.apply(to: existing))
        } else {
            _ = try await database.save(event.toRecord())
        }
    }

    // MARK: - イベント終了

    /// イベントを終了する（ユーザーの明示的な操作でのみ呼ばれる）。
    ///
    /// 旅行・合宿など複数日にまたがるイベントを想定し、**日付が変わるだけでは
    /// 終了しない**。終了はユーザーが自分で判断して行う操作。
    ///
    /// 終了しても写真は一切消えない。**タイムカプセルの公開予定もそのまま残る**。
    /// Event Reelもここでは作らない。シェアOKの写真が増えるたびに
    /// イベント中随時作られている（`ShareCollageBuilder.buildIfNeeded`）ため、
    /// 終了をきっかけに何かを生成する必要はない。
    ///
    /// 終了は**そのイベントだけ**に効く操作。`currentEvent` を外して
    /// タイトル画面に戻すが、参加履歴（`joinedEventIDs`）からは外さないので、
    /// 他に参加しているイベントには一切影響しない。ホーム画面の
    /// 「参加中のイベント」からいつでもまた開ける（新しい写真の追加はできない）。
    @discardableResult
    func endEvent() async throws -> Event? {
        guard var event = currentEvent, event.isActive else { return nil }

        event.endedAt = Date()
        event.isActive = false

        do {
            try await save(event)
            print("✅ イベント終了")

            currentEvent = nil
            participants = []
            saveCurrentEventID(nil)
            await loadRecentEvents()

            return event
        } catch {
            print("❌ イベント終了失敗: \(error)")
            throw error
        }
    }

    // MARK: - 内部

    private func applyCurrent(_ event: Event) {
        currentEvent = event
        saveCurrentEventID(event.id)
        participants = makeParticipants(from: event)
    }

    /// participantIDs から表示用の参加者一覧を組み立てる。
    /// 端末名はCloudKitに保存していないため、自分以外は連番の仮名で表示する。
    private func makeParticipants(from event: Event) -> [Participant] {
        let me = DeviceIdentity.current
        var othersCount = 0

        return event.participantIDs.map { id in
            if id == me {
                return Participant(id: id, deviceName: DeviceIdentity.displayName, joinedAt: event.createdAt)
            }
            othersCount += 1
            return Participant(id: id, deviceName: "参加者\(othersCount)", joinedAt: event.createdAt)
        }
    }
}

// MARK: - エラー

enum EventError: LocalizedError {
    case invalidID
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidID: return "無効なイベントIDです"
        case .notFound:  return "イベントが見つかりません"
        }
    }
}
