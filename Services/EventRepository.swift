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

    /// 履歴の先頭に持ち上げる（重複は取り除く）
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
    /// 以前は `joinEvent` を呼び直していたが、それだと起動のたびに
    /// 参加処理（participantIDsの書き込み）が走ってしまう。
    /// 復元は **読み取りのみ** で行い、参加者リストは触らない。
    func restoreEvent() async {
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

        let deviceID = DeviceIdentity.current

        let event = Event(
            name: name,
            creatorID: deviceID,
            participantIDs: [deviceID]
        )

        let record = event.toRecord()

        do {
            _ = try await database.save(record)
            applyCurrent(event)
            rememberEvent(event.id)
            await loadRecentEvents()

            print("✅ イベント作成成功: \(event.id) / コード: \(event.inviteCode)")
            return event
        } catch {
            print("❌ イベント作成失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - イベント参加

    /// イベントIDで参加（QRコード・ユニバーサルリンク経由）
    func joinEvent(eventID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard UUID(uuidString: eventID) != nil else {
            throw EventError.invalidID
        }

        guard let event = try await fetchEvent(id: eventID) else {
            throw EventError.notFound
        }

        try await join(event)
    }

    /// 招待コードで参加（その場にいない相手向け）
    func joinEvent(inviteCode rawCode: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let code = InviteCode.normalize(rawCode)
        guard InviteCode.isValid(code) else {
            throw EventError.invalidCode
        }

        guard let event = try await fetchEvent(inviteCode: code) else {
            throw EventError.codeNotFound
        }

        try await join(event)
    }

    /// 参加者リストに自分を加えて現在のイベントにする
    private func join(_ event: Event) async throws {
        var event = event
        let deviceID = DeviceIdentity.current

        if !event.participantIDs.contains(deviceID) {
            event.participantIDs.append(deviceID)
            do {
                _ = try await database.save(event.toRecord())
            } catch {
                print("❌ 参加者リストの更新に失敗: \(error)")
                self.error = error
                throw error
            }
        }

        applyCurrent(event)
        rememberEvent(event.id)
        await loadRecentEvents()

        print("✅ イベント参加成功: \(event.name)")
    }

    // MARK: - グループ切り替え

    /// 参加済みイベントを読み込む（切り替え画面用）
    func loadRecentEvents() async {
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
                // 通信エラーは無視する。取得できたものだけ並べる。
                print("⚠️ 履歴イベントの取得に失敗: \(id)")
            }
        }

        // 消えていたイベントは履歴から外す
        if !missing.isEmpty {
            joinedEventIDs = joinedEventIDs.filter { !missing.contains($0) }
        }

        recentEvents = loaded
    }

    /// 別のイベントに切り替える。
    /// すでに参加済みのイベントなので、参加者リストへの書き込みは行わない。
    func switchEvent(to event: Event) async {
        guard event.id != currentEvent?.id else { return }

        // 表示を即座に切り替えたうえで、最新の状態を取り直す
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

        if currentEvent?.id == event.id {
            saveCurrentEventID(nil)
            currentEvent = nil
            participants = []
        }

        await loadRecentEvents()

        // 他に参加中のイベントがあれば自動で切り替える
        if currentEvent == nil, let next = recentEvents.first {
            await switchEvent(to: next)
        }
    }

    // MARK: - イベント取得

    /// イベント情報を更新
    func refreshEvent() async throws {
        guard let event = currentEvent else { return }

        if let updated = try await fetchEvent(id: event.id.uuidString) {
            applyCurrent(updated)
        }

        await loadRecentEvents()
    }

    private func fetchEvent(id: String) async throws -> Event? {
        let predicate = NSPredicate(format: "id == %@", id)
        return try await fetchEvent(matching: predicate)
    }

    private func fetchEvent(inviteCode: String) async throws -> Event? {
        let predicate = NSPredicate(format: "inviteCode == %@", inviteCode)
        return try await fetchEvent(matching: predicate)
    }

    private func fetchEvent(matching predicate: NSPredicate) async throws -> Event? {
        let query = CKQuery(recordType: "Event", predicate: predicate)
        let results = try await database.records(matching: query)

        guard let (_, result) = results.matchResults.first,
              let record = try? result.get() else {
            return nil
        }

        return Event.from(record: record)
    }

    // MARK: - イベント終了

    /// イベントを終了
    func endEvent() async throws {
        guard var event = currentEvent else { return }

        event.endedAt = Date()
        event.isActive = false

        do {
            _ = try await database.save(event.toRecord())
            applyCurrent(event)
            print("✅ イベント終了")
        } catch {
            print("❌ イベント終了失敗: \(error)")
            throw error
        }
    }

    // MARK: - 内部

    /// 現在のイベントを差し替え、付随する状態も揃える
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
    case invalidCode
    case codeNotFound

    var errorDescription: String? {
        switch self {
        case .invalidID:    return "無効なイベントIDです"
        case .notFound:     return "イベントが見つかりません"
        case .invalidCode:  return "招待コードは6文字で入力してください"
        case .codeNotFound: return "この招待コードのイベントは見つかりませんでした"
        }
    }
}
