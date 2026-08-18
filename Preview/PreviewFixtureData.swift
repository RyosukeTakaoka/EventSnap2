//
//  PreviewFixtureData.swift
//  EventSnap
//
//  スクリーンショット撮影用の、完全に固定されたイベント・参加者・写真の定義。
//

#if DEBUG

import Foundation

/// 撮影モードで注入するデータの定義表。
///
/// ## 再現性の担保
///
/// - UUIDはすべて固定（`uuid(_:)`で連番から組み立てる）
/// - 日時は `install` 時に一度だけ確定する `anchor` からの相対値のみ
///   （「3時間前」「2日後」のように書くことで、いつ撮っても表示が自然になり、
///     かつ1回の起動の中では完全に固定される）
/// - 乱数は一切使わない（画像生成も`index`の純粋関数）
///
/// ## シーンごとにデータを変える理由
///
/// アルバム(`albumGrid`)とタイムカプセル(`timeCapsule`)は同じ`AlbumView`を撮る。
/// 専用のタイムカプセル画面がアプリに存在しないため、**写真の構成そのものを
/// 変えて**2枚が別の価値を語るようにする:
///
/// - `albumGrid`   … 18枚中ロックは2枚だけ。実写がグリッドを埋め尽くす絵
///                   →「みんなの写真が自動で集まる」
/// - `timeCapsule` … 18枚中ロックが7枚。しかも上位3行に集中させる
///                   →「まだ開いていない思い出がある」
enum PreviewFixtureData {

    // MARK: - 固定UUID

    /// 連番から決定論的にUUIDを組み立てる。
    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "5E1F0000-0000-4000-A000-\(String(format: "%012d", n))")
            ?? UUID(uuidString: "5E1F0000-0000-4000-A000-000000000000")!
    }

    static let eventID = uuid(1)
    static let pastEventID = uuid(2)

    static func photoID(_ index: Int) -> UUID { uuid(1_000 + index) }

    // MARK: - 参加者

    static let participantNames = [
        "ゆうた", "みなみ", "けんと", "さくら", "りく", "あおい",
        "はると", "ひなた", "そうた", "つむぎ", "かえで", "いつき"
    ]

    static func participantID(_ index: Int) -> String {
        "preview-participant-\(String(format: "%02d", index))"
    }

    static func participants(joinedAt: Date) -> [Participant] {
        participantNames.enumerated().map { index, name in
            Participant(
                id: participantID(index),
                deviceName: name,
                joinedAt: joinedAt.addingTimeInterval(Double(index) * 90)
            )
        }
    }

    // MARK: - イベント

    /// 表示上の写真枚数。
    ///
    /// `Event.photoCount`はCloudKit側で加算される仕組みが無く本番では常に0だが
    /// （`ShareCollageBuilder`のコメント参照）、招待画面の「◯枚」が0のままだと
    /// 実態と食い違うため、Fixtureでは実際に賑わっている値を入れる。
    static let displayedPhotoCount = 128

    static func event(anchor: Date) -> Event {
        Event(
            id: eventID,
            name: "夏フェス2026",
            createdAt: anchor.addingTimeInterval(-6 * 3600),
            creatorID: participantID(0),
            participantIDs: (0..<participantNames.count).map(participantID),
            photoCount: displayedPhotoCount,
            isActive: true
        )
    }

    /// ホーム画面・イベント切り替えに履歴として並ぶ、終了済みのイベント。
    static func pastEvent(anchor: Date) -> Event {
        Event(
            id: pastEventID,
            name: "卒業旅行 in 沖縄",
            createdAt: anchor.addingTimeInterval(-32 * 24 * 3600),
            endedAt: anchor.addingTimeInterval(-29 * 24 * 3600),
            creatorID: participantID(3),
            participantIDs: (0..<7).map(participantID),
            photoCount: 214,
            isActive: false
        )
    }

    // MARK: - 写真の構成

    /// 写真1枚分の定義。`index`がそのままグリッドの並び順になる
    /// （`uploadedAt`を`index`の降順で振るため。`AlbumViewModel.items`は
    ///  公開済みとロック中を`uploadedAt`の新しい順に混ぜて並べる）。
    struct PhotoSpec {
        let index: Int
        let isTimeCapsule: Bool
        /// 公開までの時間。`isTimeCapsule`のときだけ意味を持つ
        let revealInHours: Double
        let isShareOK: Bool
        let uploader: Int
    }

    /// 合計枚数（3列グリッドなので6行分）
    static let photoCount = 18

    /// シーンごとの「ロックされている写真のグリッド位置」。
    private static func lockedIndices(for scene: ScreenshotScene) -> [Int] {
        switch scene {
        case .timeCapsule:
            // 上位3行に集中させ、砂時計が主役に見える構成にする
            return [0, 2, 3, 5, 6, 8, 11]
        case .albumGrid, .camera, .eventReel, .invite:
            // 実写がグリッドを埋め尽くす中に、ロックが控えめに混ざる構成
            return [7, 16]
        }
    }

    /// 公開までの残り時間のバリエーション（`vagueCountdown`が
    /// 「もうすぐ公開」「数日後に公開」「今週中に公開」と散らばるように選ぶ）。
    private static let revealHourVariants: [Double] = [20, 52, 3, 96, 150, 260, 320]

    static func photoSpecs(for scene: ScreenshotScene) -> [PhotoSpec] {
        let locked = Set(lockedIndices(for: scene))
        var lockedSeen = 0

        return (0..<photoCount).map { index in
            let isLocked = locked.contains(index)
            let revealInHours: Double
            if isLocked {
                revealInHours = revealHourVariants[lockedSeen % revealHourVariants.count]
                lockedSeen += 1
            } else {
                revealInHours = 0
            }

            return PhotoSpec(
                index: index,
                isTimeCapsule: isLocked,
                revealInHours: revealInHours,
                // 公開済みの写真はすべてEvent Reelの材料になりうる状態にしておく
                isShareOK: !isLocked,
                uploader: index % participantNames.count
            )
        }
    }

    /// 定義からPhotoを組み立てる。
    ///
    /// `imageURLs`/`thumbnailURLs`はローカルの`file://`。CKAssetの`fileURL`と
    /// 同じ形なので、`PhotoImageLoader`は一切の改造なしにこれを読み込める。
    static func photos(
        for scene: ScreenshotScene,
        anchor: Date,
        imageURLs: [URL],
        thumbnailURLs: [URL]
    ) -> [Photo] {
        photoSpecs(for: scene).compactMap { spec in
            guard spec.index < imageURLs.count, spec.index < thumbnailURLs.count else { return nil }

            // indexが大きいほど古い。これでグリッドの並び順がindex順に固定される。
            let uploadedAt = anchor.addingTimeInterval(-1_200 - Double(spec.index) * 420)

            return Photo(
                id: photoID(spec.index),
                eventID: eventID,
                uploaderID: participantID(spec.uploader),
                uploaderName: participantNames[spec.uploader],
                uploadedAt: uploadedAt,
                imageURL: imageURLs[spec.index],
                thumbnailURL: thumbnailURLs[spec.index],
                filterName: nil,
                aiProcessed: false,
                isTimeCapsule: spec.isTimeCapsule,
                revealDate: spec.isTimeCapsule
                    ? anchor.addingTimeInterval(spec.revealInHours * 3600)
                    : nil,
                isShareOK: spec.isShareOK
            )
        }
    }

    // MARK: - Event Reel の構成

    /// 1件目から順に、何枚ずつまとめてEvent Reelにするか。
    /// 本番の`ShareCollageBuilder`が3〜5枚で1件を作るのに合わせている。
    static let reelChunkSizes = [4, 5, 3]

    /// シェアOKかつ公開済みの写真を、上記の枚数ずつに区切る。
    /// 材料が足りないシーン（ロックが多い`timeCapsule`）では作れる分だけ作る。
    static func reelGroups(from photos: [Photo]) -> [[Photo]] {
        // 本番と同じく「古い順に区切っていく」
        var remaining = photos
            .filter { $0.isShareOK && !$0.isTimeCapsule }
            .sorted { $0.uploadedAt < $1.uploadedAt }

        var groups: [[Photo]] = []
        for size in reelChunkSizes {
            guard remaining.count >= 2 else { break }
            let take = min(size, remaining.count)
            groups.append(Array(remaining.prefix(take)))
            remaining.removeFirst(take)
        }
        return groups
    }
}

#endif
