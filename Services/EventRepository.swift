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
    @Published var isLoading = false
    @Published var error: Error?

    private let container = CKContainer.default()
    private var database: CKDatabase

    init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - イベント作成

    /// 新規イベントを作成
    func createEvent(name: String) async throws -> Event {
        isLoading = true
        defer { isLoading = false }

        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        let event = Event(
            name: name,
            creatorID: deviceID,
            participantIDs: [deviceID]
        )

        let record = event.toRecord()

        do {
            _ = try await database.save(record)
            self.currentEvent = event

            // 作成者を参加者に追加
            let creator = Participant(
                id: deviceID,
                deviceName: UIDevice.current.name
            )
            self.participants = [creator]

            print("✅ イベント作成成功: \(event.id)")
            return event
        } catch {
            print("❌ イベント作成失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - イベント参加

    /// 既存イベントに参加
    func joinEvent(eventID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let uuid = UUID(uuidString: eventID) else {
            throw NSError(domain: "EventRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "無効なイベントID"])
        }

        // CloudKitからイベントを検索
        let predicate = NSPredicate(format: "id == %@", uuid.uuidString)
        let query = CKQuery(recordType: "Event", predicate: predicate)

        do {
            let results = try await database.records(matching: query)

            guard let (_, result) = results.matchResults.first,
                  let record = try? result.get() else {
                throw NSError(domain: "EventRepository", code: 2, userInfo: [NSLocalizedDescriptionKey: "イベントが見つかりません"])
            }

            guard var event = Event.from(record: record) else {
                throw NSError(domain: "EventRepository", code: 3, userInfo: [NSLocalizedDescriptionKey: "イベントデータの解析に失敗"])
            }

            // 参加者リストに追加
            let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

            if !event.participantIDs.contains(deviceID) {
                event.participantIDs.append(deviceID)

                // CloudKitを更新
                let updatedRecord = event.toRecord()
                _ = try await database.save(updatedRecord)
            }

            self.currentEvent = event

            // 参加者情報を作成
            let participant = Participant(
                id: deviceID,
                deviceName: UIDevice.current.name
            )
            self.participants.append(participant)

            print("✅ イベント参加成功: \(event.name)")
        } catch {
            print("❌ イベント参加失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - イベント取得

    /// イベント情報を更新
    func refreshEvent() async throws {
        guard let event = currentEvent else { return }

        let predicate = NSPredicate(format: "id == %@", event.id.uuidString)
        let query = CKQuery(recordType: "Event", predicate: predicate)

        do {
            let results = try await database.records(matching: query)

            guard let (_, result) = results.matchResults.first,
                  let record = try? result.get(),
                  let updatedEvent = Event.from(record: record) else {
                return
            }

            self.currentEvent = updatedEvent
        } catch {
            print("❌ イベント更新失敗: \(error)")
            throw error
        }
    }

    // MARK: - イベント終了

    /// イベントを終了
    func endEvent() async throws {
        guard var event = currentEvent else { return }

        event.endedAt = Date()
        event.isActive = false

        let record = event.toRecord()

        do {
            _ = try await database.save(record)
            self.currentEvent = event
            print("✅ イベント終了")
        } catch {
            print("❌ イベント終了失敗: \(error)")
            throw error
        }
    }
}
