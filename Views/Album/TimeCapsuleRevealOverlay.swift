//
//  TimeCapsuleRevealOverlay.swift
//  EventSnap
//
//  タイムカプセルが公開された直後、アルバムを開いた瞬間に一度だけ見せる
//  簡易なお祝い演出（表示専用。Event Reel生成・CloudKit同期には一切触れない）。
//

import SwiftUI

/// アルバムを開いた際、前回訪問時から新しく公開されたタイムカプセル写真があれば
/// 一瞬だけ全画面に出す演出。ゴールド背景+サムネイル1枚+短いメッセージのみの
/// 簡易版で、派手なアニメーションは付けない。
///
/// タップ、または`autoDismissDelay`経過で自動的に閉じる。
struct TimeCapsuleRevealOverlay: View {
    let photo: Photo
    let image: UIImage?
    let onDismiss: () -> Void

    /// 演出を出しっぱなしにしないための自動クローズまでの秒数。
    private let autoDismissDelay: TimeInterval = 2.5

    @State private var isVisible = false

    var body: some View {
        ZStack {
            // タイムカプセルの他の画面（LockedPhotoCell・CameraViewトグル）と
            // 同じゴールド系グラデーションで統一する。
            DesignTokens.capsuleGradient
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("✨ 新しい思い出が届きました")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                thumbnail
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            }
            .scaleEffect(isVisible ? 1 : 0.85)
            .opacity(isVisible ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { isVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDelay) {
                onDismiss()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("新しい思い出が届きました。タップで閉じます。")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 220, height: 220)
                .clipped()
        } else {
            Image(systemName: "hourglass")
                .font(.system(size: 50))
                .foregroundColor(.white)
        }
    }
}

// MARK: - 表示済み記録

/// この演出を既に見せた写真IDの記録（端末ローカル、UserDefaults）。
/// 一度見せた写真については二度と演出を出さない。
/// `TutorialManager`と同じ、素のUserDefaultsによる簡易な状態管理に合わせている。
enum TimeCapsuleRevealHistory {
    private static let key = "timeCapsuleRevealOverlayShownPhotoIDs"
    private static let defaults = UserDefaults.standard

    static func hasShown(_ id: UUID) -> Bool {
        shownIDs.contains(id.uuidString)
    }

    static func markShown(_ id: UUID) {
        var ids = shownIDs
        ids.insert(id.uuidString)
        defaults.set(Array(ids), forKey: key)
    }

    private static var shownIDs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}

#Preview {
    TimeCapsuleRevealOverlay(
        photo: Photo(eventID: UUID(), uploaderID: "preview", isTimeCapsule: true, revealDate: Date()),
        image: nil,
        onDismiss: {}
    )
}
