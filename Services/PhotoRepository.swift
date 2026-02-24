//
//  PhotoRepository.swift
//  EventSnap
//
//  写真データ管理（CloudKit連携）
//

import Foundation
import CloudKit
import UIKit
import Combine

@MainActor
class PhotoRepository: ObservableObject {
    static let shared = PhotoRepository()

    @Published var photos: [Photo] = []
    @Published var isUploading = false
    @Published var error: Error?

    private let container = CKContainer.default()
    private var database: CKDatabase

    init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - 写真アップロード

    /// 写真をアップロード
    func uploadPhoto(_ image: UIImage, eventID: UUID, filterName: String? = nil) async throws {
        isUploading = true
        defer { isUploading = false }

        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        let photo = Photo(
            eventID: eventID,
            uploaderID: deviceID,
            filterName: filterName,
            aiProcessed: filterName != nil
        )

        // ローカルキャッシュに即座に追加（UX向上）
        self.photos.insert(photo, at: 0)

        // 画像をリサイズ（パフォーマンス向上）
        guard let resizedImage = resizeImage(image, maxSize: 1920) else {
            throw NSError(domain: "PhotoRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "画像のリサイズに失敗"])
        }

        // CloudKitレコード作成
        let record = photo.toRecord()

        // 画像データを一時ファイルに保存
        if let imageData = resizedImage.jpegData(compressionQuality: 0.8) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(photo.id.uuidString).jpg")

            try imageData.write(to: tempURL)
            record["imageAsset"] = CKAsset(fileURL: tempURL)

            // サムネイル生成
            if let thumbnail = resizeImage(resizedImage, maxSize: 300),
               let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) {
                let thumbnailURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(photo.id.uuidString)_thumb.jpg")
                try thumbnailData.write(to: thumbnailURL)
                record["thumbnailAsset"] = CKAsset(fileURL: thumbnailURL)
            }
        }

        do {
            print(record)
            _ = try await database.save(record)
            print("✅ レコードの保存に成功しました")
        } catch let error as CKError {
            // CloudKit特有のエラーを処理
            switch error.code {
            case .networkUnavailable, .networkFailure:
                print("❌ ネットワークエラー: インターネット接続を確認してください")
                
            case .notAuthenticated:
                print("❌ iCloudにサインインしていません")
                
            case .quotaExceeded:
                print("❌ iCloudストレージの容量が不足しています")
                
            case .serverRecordChanged:
                print("❌ サーバー上のレコードが変更されています（競合）")
                
            case .unknownItem:
                print("❌ 保存しようとしたレコードが見つかりません")
                
            default:
                print("❌ CloudKitエラー: \(error.localizedDescription)")
            }
        }  catch {
            // アップロード失敗時はローカルから削除
            if let index = photos.firstIndex(where: { $0.id == photo.id }) {
                photos.remove(at: index)
            }
            print("❌ 写真アップロード失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - 写真取得

    /// イベントの写真一覧を取得
    func fetchPhotos(for eventID: UUID) async throws {
        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let query = CKQuery(recordType: "Photo", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "uploadedAt", ascending: false)]

        do {
            let results = try await database.records(matching: query)

            var fetchedPhotos: [Photo] = []

            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let photo = Photo.from(record: record) {
                    fetchedPhotos.append(photo)
                }
            }

            self.photos = fetchedPhotos
            print("✅ 写真取得成功: \(fetchedPhotos.count)枚")
        } catch {
            print("❌ 写真取得失敗: \(error)")
            self.error = error
            throw error
        }
    }

    // MARK: - リアルタイム更新

    /// CloudKit Subscriptionを設定（リアルタイム同期）
    func setupSubscription(for eventID: UUID) async {
        let predicate = NSPredicate(format: "eventID == %@", eventID.uuidString)
        let subscription = CKQuerySubscription(
            recordType: "Photo",
            predicate: predicate,
            subscriptionID: "photo-added-\(eventID.uuidString)",
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            print("✅ リアルタイム同期設定完了")
        } catch {
            print("❌ Subscription設定失敗: \(error)")
        }
    }

    // MARK: - ヘルパーメソッド

    /// 画像リサイズ
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)

        if ratio >= 1 { return image }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage
    }

    /// イベントの写真カウントを更新
    private func updateEventPhotoCount(eventID: UUID) async {
        // EventRepositoryの写真カウントを更新
        // 実装は EventRepository と連携
    }
}
