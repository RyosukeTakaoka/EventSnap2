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
    private let cachedEventsKey = "cachedEvents"

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

    /// 履歴から外す。
    ///
    /// ⚠️ **呼んでよいのは、ユーザーが自分で「一覧から外す」を選んだときだけ。**
    /// CloudKitから読めなかったことを理由にここを呼んではいけない
    /// （`loadRecentEvents`のコメント参照）。
    private func forgetEvent(_ id: UUID) {
        joinedEventIDs = joinedEventIDs.filter { $0 != id.uuidString }
        cachedEvents = cachedEvents.filter { $0.id != id }
    }

    // MARK: - イベント内容のキャッシュ

    /// 最後に読み込めたイベントの中身。
    ///
    /// ## なぜ必要か
    ///
    /// 参加履歴はIDしか持っていないため、CloudKitから読めないイベントは
    /// 一覧に出しようがなく、**参加していたグループが画面から消えたように見える**。
    ///
    /// CloudKitから読めなくなる理由は「本当に消えた」だけではない。
    ///
    /// - Xcodeから入れたビルド（Development）とTestFlight/App Store版（Production）
    ///   では**保存先の環境が別**なので、ビルドを入れ替えると相手側のイベントは
    ///   一切見えなくなる
    /// - iCloudにサインインしていない／通信が不安定
    /// - サーバー側のインデックスがまだ反映されていない
    ///
    /// どれも一時的なものなので、**前回読めた内容を手元に残しておき、
    /// 読めない間もグループを一覧に出し続ける**。
    private var cachedEvents: [Event] {
        get {
            guard let data = UserDefaults.standard.data(forKey: cachedEventsKey),
                  let events = try? JSONDecoder().decode([Event].self, from: data)
            else { return [] }
            return events
        }
        set {
            guard let data = try? JSONEncoder().encode(Array(newValue.prefix(historyLimit))) else { return }
            UserDefaults.standard.set(data, forKey: cachedEventsKey)
        }
    }

    private func cachedEvent(id: String) -> Event? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return cachedEvents.first { $0.id == uuid }
    }

    private func updateCache(with event: Event) {
        var events = cachedEvents.filter { $0.id != event.id }
        events.insert(event, at: 0)
        cachedEvents = events
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
            if let event = try await fetchEvent(id: savedID) {
                applyCurrent(event)
                print("✅ イベントを復元しました: \(event.name)")
            } else if let cached = cachedEvent(id: savedID) {
                // CloudKitでは見つからないが、前回読めた内容が手元にある。
                //
                // ここで履歴を消してはいけない。「見つからない」の正体は
                // だいたいビルドの入れ替え（Development / Production の違い）で、
                // 元のビルドに戻せばまた見えるようになる。消してしまうと
                // **二度と戻せない**（詳細は`cachedEvents`のコメント）。
                applyCurrent(cached)
                print("⚠️ CloudKitから読めないため、保存済みの内容で復元しました: \(cached.name)")
            } else {
                print("⚠️ 保存されていたイベントを復元できませんでした（履歴は保持）: \(savedID)")
            }
        } catch {
            // 通信エラー。キャッシュがあればそれで開き、無ければ次回の起動でやり直す。
            if let cached = cachedEvent(id: savedID) {
                applyCurrent(cached)
            }
            print("⚠️ イベントの復元に失敗（履歴は保持）: \(error)")
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

        guard let uuid = UUID(uuidString: eventID) else {
            print("❌ QRから読み取った文字列がイベントIDの形式ではありません: \(eventID)")
            throw EventError.invalidID
        }

        // 参加者リストへの書き込みが発生するので、先にiCloudを確認する
        try await CloudKitAccount.ensureAvailable()

        guard let event = try await fetchEvent(id: eventID) else {
            // 「見つからない」で終わらせず、切り分けに要る材料をログに残す。
            // 実際の原因はほぼ次のどれかで、画面のメッセージだけでは区別できない。
            //   1. 主催者と参加者で CloudKit の環境が違う
            //      （Xcodeから直接入れたビルド＝Development、
            //        TestFlight／App Store版＝Production。両者のデータは別物）
            //   2. 主催者側でイベントの作成そのものが失敗していた
            //   3. 読み取ったQRが別コンテナ／別アプリのもの
            print("""
            ❌ イベントが見つかりません
               eventID   : \(eventID)
               recordName: \(Event.recordID(for: uuid).recordName)
               container : \(container.containerIdentifier ?? "不明")
               主催者の端末と同じCloudKit環境(Development / Production)かを確認してください。
            """)
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

        // まず手元のキャッシュで埋めておき、読めたものだけ最新版で上書きする。
        //
        // ⚠️ **読めなかったイベントを履歴から消してはいけない。**
        // 以前はここで消していたため、ビルドを入れ替えた（Development ⇄ Production）
        // だけで参加履歴が丸ごと吹き飛び、元のビルドに戻しても
        // **二度と戻らない**という壊れ方をしていた。
        // 「今回読めなかった」ことは「そのイベントが消えた」ことを意味しない。
        //
        // 履歴から外れるのは、ユーザーが自分で「一覧から外す」を選んだときだけ
        // （`leaveEvent` → `forgetEvent`）。
        var byID = Dictionary(cachedEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in ids {
            do {
                if let event = try await fetchEvent(id: id) {
                    byID[event.id] = event
                } else {
                    print("⚠️ 履歴イベントが見つかりません（履歴は保持）: \(id)")
                }
            } catch {
                print("⚠️ 履歴イベントの取得に失敗（履歴は保持）: \(id) / \(error)")
            }
        }

        // 履歴の並び（最近使った順）を保ったまま、読めたもの・キャッシュにあるものを並べる
        let ordered = ids.compactMap { UUID(uuidString: $0) }.compactMap { byID[$0] }

        recentEvents = ordered
        cachedEvents = ordered
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

    /// イベントの取得結果。
    ///
    /// **「本当に存在しない」と「読めなかった」を必ず区別する**ためのもの。
    /// 以前はどちらも `nil` で返していたため、CloudKitのスキーマ不備や通信の
    /// 問題まで「イベントが見つかりません」として扱われ、さらに
    /// `loadRecentEvents` が参加履歴からそのグループを消してしまっていた。
    private enum EventLookup {
        /// 読み込めた
        case found(Event)
        /// このIDのレコードは、この環境に確かに存在しない
        case absent
        /// レコードは在るのに Event として読めなかった（IDが壊れている等）
        case unreadable
    }

    /// 「本当に無い」ときだけ `nil` を返す。
    /// 読めなかった場合は `EventError.unreadable` を投げる（`nil` にはしない）。
    private func fetchEvent(id: String) async throws -> Event? {
        switch try await lookupEvent(id: id) {
        case .found(let event): return event
        case .absent:          return nil
        case .unreadable:      throw EventError.unreadable
        }
    }

    /// イベントのレコードを取得する。`nil` は「この環境に確かに無い」。
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
        } catch let error as CKError where error.isUnknownItem {
            // このIDのレコードは無い。旧形式の可能性があるので②へ。
        } catch {
            throw error
        }

        // ② 旧バージョンが作ったレコードは recordName がランダムなので
        //    フィールド検索でしか見つけられない
        let predicate = NSPredicate(format: "id == %@", id)
        let query = CKQuery(recordType: "Event", predicate: predicate)

        let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            matchResults = try await database.records(matching: query).matchResults
        } catch let error as CKError where error.isSchemaProblem {
            // ここに来るのは「レコードが無い」ではなく **スキーマの問題**。
            //
            // - `unknownItem`: この環境に `Event` レコードタイプ自体が無い
            //   （Production へ Deploy Schema Changes をしていない、など）
            // - `invalidArguments`: `id` フィールドが Queryable になっていない
            //
            // 「イベントが見つかりません」と伝えてしまうと原因を永久に追えないので、
            // スキーマの問題として区別して投げる。
            print("❌ Eventのクエリがスキーマ都合で失敗しました: \(error)")
            throw EventError.schemaUnavailable(error.localizedDescription)
        }

        guard let (_, result) = matchResults.first else { return nil }
        return try? result.get()
    }

    /// レコードを取りに行き、「無い」「読めない」「読めた」を区別して返す。
    private func lookupEvent(id: String) async throws -> EventLookup {
        guard let record = try await fetchRecord(id: id) else { return .absent }

        if let event = Event.from(record: record) { return .found(event) }

        print("⚠️ Eventレコードは存在しますが読み取れませんでした: \(record.recordID.recordName)")
        return .unreadable
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
        // 次に読めなくなったときのために、開いた内容を手元にも残しておく
        updateCache(with: event)
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
    /// レコードは在るのに Event として読み込めなかった
    case unreadable
    /// CloudKit のスキーマ側の問題（レコードタイプが無い／インデックス未設定）
    case schemaUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidID:
            return "無効なイベントIDです"
        case .notFound:
            // 「無い」と断定できたときだけ出す。原因の切り分けができるよう、
            // よくある理由（作成側と別のiCloud環境で動かしている等）も添える。
            return """
            このイベントは見つかりませんでした。

            ・主催者がイベントを終了・削除していないか
            ・主催者と同じバージョンのアプリか
              （Xcodeから入れたアプリとTestFlight／App Store版では
              　保存先のiCloud環境が別になり、お互いのイベントが見えません）
            をご確認ください。
            """
        case .unreadable:
            return "イベントの情報を読み取れませんでした。\nアプリを最新版に更新してからお試しください。"
        case .schemaUnavailable(let detail):
            return "サーバー（iCloud）の設定が未反映のようです。\n(\(detail))"
        }
    }
}

// MARK: - CKError の判定ヘルパー

extension CKError {

    /// 「そのレコードは無い」を表すか。
    ///
    /// `CKDatabase.record(for:)` は、内部の一括取得の都合で
    /// **`.partialFailure` の中に `.unknownItem` を包んで**投げてくることがある。
    /// トップレベルのコードだけを見ていると取りこぼし、「無いだけ」なのに
    /// 予期しないエラーとして扱ってしまう。
    var isUnknownItem: Bool {
        if code == .unknownItem { return true }
        guard code == .partialFailure,
              let partial = partialErrorsByItemID?.values else { return false }
        return partial.contains { ($0 as? CKError)?.code == .unknownItem }
    }

    /// スキーマ側の不備（レコードタイプが無い／フィールドが Queryable でない）か。
    /// クエリでこれらが返るのは「該当なし」ではなく設定の問題。
    var isSchemaProblem: Bool {
        isUnknownItem || code == .invalidArguments
    }
}
