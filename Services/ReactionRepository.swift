//
//  ReactionRepository.swift
//  EventSnap
//
//  写真への絵文字リアクション管理（CloudKit連携）
//

import Foundation
import CloudKit

@MainActor
class ReactionRepository: ObservableObject {
    static let shared = ReactionRepository()

    /// 現在のイベントの全リアクション。写真ごとの絞り込みは呼び出し側で行う。
    @Published var reactions: [Reaction] = []

    private let container = CKContainer.default()
    private var database: CKDatabase

    init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - 取得

    /// イベント全体のリアクションをまとめて取得する。
    /// 写真ごとに毎回クエリを投げるとアルバムを開くたびに大量のリクエストに
    /// なるため、`PhotoRepository.fetchPhotos`と同じく1イベント分をまとめて取る。
    func fetchReactions(for eventID: UUID) async throws {
        guard !ScreenshotMode.suppressesLiveServices else { return }

        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Reaction", predicate: predicate)

        do {
            let results = try await database.records(matching: query)
            var fetched: [Reaction] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(), let reaction = Reaction.from(record: record) {
                    fetched.append(reaction)
                }
            }
            self.reactions = fetched
        } catch let error as CKError where error.code == .unknownItem {
            // Reactionレコードタイプ自体がまだこの環境に無い（スキーマ未反映）。
            // リアクション機能が無いだけとして扱い、他の写真表示は妨げない。
            print("⚠️ Reactionレコードタイプが見つかりません。CloudKitのスキーマ設定を確認してください")
            self.reactions = []
        }
    }

    // MARK: - リアクションの変更

    /// 自分のリアクションを設定する。
    /// - 既に同じ絵文字を選んでいた場合は取り消す（トグル）
    /// - 別の絵文字を選んでいた場合は付け替える
    /// - まだ選んでいない場合は新しく付ける
    ///
    /// 1人が1枚の写真に持てるリアクションは常に1個まで
    /// （複数の絵文字を同時に付けることはできない）。
    func toggleReaction(_ emoji: String, photoID: UUID, event: Event) async {
        let reactorID = DeviceIdentity.current

        if let existing = reactions.first(where: { $0.photoID == photoID && $0.reactorID == reactorID }) {
            if existing.emoji == emoji {
                await remove(existing)
            } else {
                var updated = existing
                updated.emoji = emoji
                await upsert(updated)
            }
        } else {
            let new = Reaction(eventID: event.id, photoID: photoID, reactorID: reactorID, emoji: emoji, createdAt: Date())
            await upsert(new)
        }
    }

    /// 自分がその写真に付けているリアクション（無ければnil）
    func myReaction(for photoID: UUID) -> String? {
        reactions.first { $0.photoID == photoID && $0.reactorID == DeviceIdentity.current }?.emoji
    }

    /// その写真に付いているリアクションの種類を、古い順に重複無しで返す。
    /// **誰が何個押したかは一切集計しない**。写真の隅に絵文字を並べて見せる
    /// だけの、数字の出ないリアクション表示に使う。
    func emojiSummary(for photoID: UUID) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for reaction in reactions.filter({ $0.photoID == photoID }).sorted(by: { $0.createdAt < $1.createdAt }) {
            if seen.insert(reaction.emoji).inserted {
                order.append(reaction.emoji)
            }
        }
        return order
    }

    private func upsert(_ reaction: Reaction) async {
        do {
            try await save(reaction)
        } catch {
            print("❌ リアクションの保存に失敗 (\(reaction.photoID)): \(error)")
            return
        }

        if let index = reactions.firstIndex(where: { $0.id == reaction.id }) {
            reactions[index] = reaction
        } else {
            reactions.append(reaction)
        }
    }

    private func remove(_ reaction: Reaction) async {
        do {
            _ = try await database.deleteRecord(withID: reaction.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // CloudKit上にはもう無い。ローカルだけ整合させる。
        } catch {
            print("❌ リアクションの削除に失敗 (\(reaction.photoID)): \(error)")
            return
        }

        reactions.removeAll { $0.id == reaction.id }
    }

    /// レコードを保存する（既存があれば上書き、無ければ新規作成）。
    /// recordIDが(photoID, reactorID)から決まるため、Event/Photoと違って
    /// クエリへのフォールバックは要らない（旧形式のランダムなrecordNameが
    /// 存在しない、新規追加のレコードタイプのため）。
    private func save(_ reaction: Reaction) async throws {
        do {
            let existing = try await database.record(for: reaction.recordID)
            _ = try await database.save(reaction.apply(to: existing))
        } catch let error as CKError where error.code == .unknownItem {
            _ = try await database.save(reaction.toRecord())
        }
    }

    // MARK: - リアルタイム更新

    /// リアクションはEmoji変更（付け替え）も他の参加者に届く必要があるため、
    /// 作成だけでなく更新・削除でも発火するサブスクリプションにする
    /// （`PhotoRepository.setupSubscription`は作成のみで足りるが、こちらは違う）。
    func setupSubscription(for eventID: UUID) async {
        guard !ScreenshotMode.suppressesLiveServices else { return }

        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let subscription = CKQuerySubscription(
            recordType: "Reaction",
            predicate: predicate,
            subscriptionID: "reaction-changed-\(eventID.uuidString)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
        } catch {
            print("❌ リアクションのSubscription設定失敗: \(error)")
        }
    }
}
