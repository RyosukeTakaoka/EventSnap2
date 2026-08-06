//
//  ShareCollageStore.swift
//  EventSnap
//
//  生成したコラージュ画像のローカル保存
//

import Foundation
import UIKit

/// 生成したコラージュをアプリ内に置いておき、後からでも見返せるようにする。
///
/// CloudKitには上げない。コラージュは各自の端末で同じ素材から作られるものであり、
/// 共有ストレージに置くと「シェアOKにしていない写真が混ざっていないか」を
/// 検証できる場所が増えてしまうため。
@MainActor
final class ShareCollageStore: ObservableObject {
    static let shared = ShareCollageStore()

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ShareCollages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for eventID: UUID) -> URL {
        directory.appendingPathComponent("\(eventID.uuidString).jpg")
    }

    func hasCollage(for eventID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: eventID).path)
    }

    func save(_ image: UIImage, for eventID: UUID) throws {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CollageError.encodingFailed
        }
        try data.write(to: url(for: eventID), options: .atomic)
        print("💾 コラージュを保存しました: \(eventID.uuidString)")
        objectWillChange.send()
    }

    func load(for eventID: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: eventID)) else { return nil }
        return UIImage(data: data)
    }

    /// 共有シートに渡すためのファイルURL（画像そのものより取り回しが良い）
    func fileURL(for eventID: UUID) -> URL? {
        let url = url(for: eventID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func delete(for eventID: UUID) {
        try? FileManager.default.removeItem(at: url(for: eventID))
        objectWillChange.send()
    }
}

enum CollageError: LocalizedError {
    case noApprovedPhotos
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noApprovedPhotos:
            return "シェアが許可された写真がありません"
        case .encodingFailed:
            return "コラージュ画像の保存に失敗しました"
        }
    }
}
