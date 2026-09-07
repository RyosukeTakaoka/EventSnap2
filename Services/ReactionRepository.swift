//
//  ReactionRepository.swift
//  EventSnap
//
//  写真への絵文字リアクション管理（CloudKit連携）
//
//  **件数は一切集計しない。** 出すのは「どの絵文字を、誰が押したか」だけ。
//  InstagramやYouTubeの「いいね◯件」のような数字は、EventSnapの
//  「その場に居合わせた人だけの、飾らない集まり」というコンセプトに
//  合わないという判断で意図的に作っていない。
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
        } catch let error as CKError where error.code == .unknownItem || error.code == .invalidArguments {
            // ここに来るのはスキーマ側の準備がまだ終わっていないとき。
            //
            // - `unknownItem`      : この環境に`Reaction`レコードタイプがまだ無い
            //                        （誰も一度もリアクションしていない＝自動生成前）
            // - `invalidArguments` : `eventID`がQueryableになっていない
            //
            // どちらもリアクションが1件も無いのと同じ扱いにして、
            // アルバムの写真表示までは巻き添えで止めない。
            print("⚠️ リアクションを取得できませんでした（スキーマ未整備の可能性）: \(error.localizedDescription)")
            self.reactions = []
        }
    }

    // MARK: - リアクションの変更

    /// 自分のリアクションを付ける／外す（同じ絵文字をもう一度で取り消し）。
    ///
    /// **1人が同じ写真に何種類でも押せる。** 絵文字ごとに別レコードなので、
    /// ある絵文字を押す・外す操作が他の絵文字に影響しない。
    func toggleReaction(_ emoji: String, photoID: UUID, event: Event) async {
        let reactorID = DeviceIdentity.current

        if let existing = reactions.first(where: {
            $0.photoID == photoID && $0.reactorID == reactorID && $0.emoji == emoji
        }) {
            await remove(existing)
        } else {
            let new = Reaction(
                eventID: event.id,
                photoID: photoID,
                reactorID: reactorID,
                reactorName: DeviceIdentity.displayName,
                emoji: emoji,
                createdAt: Date()
            )
            await add(new)
        }
    }

    /// 自分がその写真に付けている絵文字（複数可）
    func myReactions(for photoID: UUID) -> Set<String> {
        let me = DeviceIdentity.current
        return Set(reactions.filter { $0.photoID == photoID && $0.reactorID == me }.map(\.emoji))
    }

    /// その写真へのリアクションを押された順に返す（「誰が押したか」の一覧用）。
    /// プロパティの`reactions`と紛らわしくならないよう、別の名前にしている。
    func sortedReactions(for photoID: UUID) -> [Reaction] {
        reactions.filter { $0.photoID == photoID }.sorted { $0.createdAt < $1.createdAt }
    }

    /// その写真に付いているリアクションの種類を、古い順に重複無しで返す。
    /// **何件付いているかは数えない**。アルバムのグリッドで、写真の隅に
    /// 絵文字を並べて見せるだけの表示に使う。
    func emojiSummary(for photoID: UUID) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for reaction in sortedReactions(for: photoID) {
            if seen.insert(reaction.emoji).inserted {
                order.append(reaction.emoji)
            }
        }
        return order
    }

    private func add(_ reaction: Reaction) async {
        // 先にローカルへ反映して、タップに即座に反応させる。
        // 失敗したら元に戻す（`PhotoRepository.uploadPhoto`のrollbackと同じ考え方）。
        reactions.append(reaction)

        do {
            _ = try await database.save(reaction.toRecord())
        } catch let error as CKError where error.code == .serverRecordChanged {
            // 既に同じレコードがサーバーにある（別端末から同期される前に押した等）。
            // 押したという結果自体は同じなので、ローカルはそのままでよい。
        } catch {
            print("❌ リアクションの保存に失敗 (\(reaction.photoID)): \(error)")
            reactions.removeAll { $0.id == reaction.id }
        }
    }

    private func remove(_ reaction: Reaction) async {
        reactions.removeAll { $0.id == reaction.id }

        do {
            _ = try await database.deleteRecord(withID: reaction.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // CloudKit上にはもう無い。ローカルだけ整合させればよい。
        } catch {
            print("❌ リアクションの削除に失敗 (\(reaction.photoID)): \(error)")
            reactions.append(reaction)
        }
    }

    // MARK: - リアルタイム更新

    /// リアクションは付け外しの両方が他の参加者に届く必要があるため、
    /// 作成だけでなく削除でも発火するサブスクリプションにする
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
            // スキーマ未整備のうちは失敗する。リアクション自体が使えないだけなので、
            // 他の同期は止めずに次回の起動でやり直す。
            print("❌ リアクションのSubscription設定失敗: \(error.localizedDescription)")
        }
    }
}
