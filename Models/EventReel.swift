//
//  EventReel.swift
//  EventSnap
//
//  イベント中に育っていくシェア画像（Event Reel）の1件分
//

import Foundation

/// シェアOKの写真がまとまった数（`ShareCollageBuilder.minPhotosForNewReel`〜
/// `maxPhotosPerReel`枚、通常3〜5枚）集まるたびに生成される、EventSnapが
/// 自動編集した複数写真のシェア画像1件分のメタ情報。
///
/// `photoIDs`が複数枚を保持できるのはこのため。ある1件のReelは「その時間帯に
/// 集まったシェアOK写真から、品質と多様性を見て選ばれた数枚」を表す
/// （選定ロジックは`EventReelPhotoSelector`）。
///
/// 生成しても古いReelは消さず、イベント内に複数保存して履歴として残す
/// （「Event Reel #1」「#2」…と育っていく体験にするため）。
/// 画像本体はCloudKitには上げず、各端末のローカルに保存する
/// （`ShareCollageStore`）。誰の端末でも同じ材料から同じ結果が組み立てられるため、
/// 共有ストレージに置く必要が無い。
///
/// **完全に固定されたスナップショットではない**。写真のシェアOKが後から
/// OFFに変わった場合、そのIDは `photoIDs` から取り除かれ、画像も作り直される
/// （`ShareCollageBuilder.removeFromReels`）。生成した記録（`index`・`builtAt`）
/// 自体は保持し、中身だけが「現在のシェアOK状態」を反映して更新される。
///
/// 過去バージョンで生成された`photoIDs.count == 1`のReelも端末に残り得るため、
/// 表示側（`SocialCardShareView`）はその場合だけ旧来の単写真フローにフォールバックする。
struct EventReel: Identifiable, Codable, Equatable {
    let id: UUID
    let eventID: UUID
    /// 生成順（1から始まる連番）。「Event Reel #N」の表示に使う
    let index: Int
    let builtAt: Date
    /// このReelを構成している写真のID一覧（通常3〜5枚、最大`ShareCollageBuilder.maxPhotosPerReel`）。
    /// shareOKが後からOFFになった写真はここから取り除かれる。
    var photoIDs: [UUID]

    init(
        id: UUID = UUID(),
        eventID: UUID,
        index: Int,
        builtAt: Date = Date(),
        photoIDs: [UUID]
    ) {
        self.id = id
        self.eventID = eventID
        self.index = index
        self.builtAt = builtAt
        self.photoIDs = photoIDs
    }
}
