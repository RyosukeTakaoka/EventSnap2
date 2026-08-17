//
//  EventActivityWidget.swift
//  EventSnapWidget
//
//  Live Activity(Dynamic Island / ロック画面)のUI定義。
//  状態(EventActivityAttributes.ContentState)自体はメインアプリの
//  `EventActivityManager`が更新する。ここは表示を組み立てるだけ。
//
//  **配色の方針**: ロック画面もDynamic Islandも常に暗い背景+白文字で統一する。
//  Dynamic Islandはシステムが常に黒背景にするため、以前ロック画面だけ明るい
//  背景にしていたときは`.primary`/`.secondary`任せの文字が白いまま残って
//  「文字が見えなくなる」不具合が起きていた。暗背景に統一し、文字色も
//  常に明示的に白系を指定することで、その不具合の芽ごと無くしている。
//

import ActivityKit
import SwiftUI
import WidgetKit

struct EventActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .widgetURL(deepLink(for: context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.icon)
                        .font(.system(size: 34))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    shutterLink(eventIDString: context.attributes.eventID, size: 50)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.eventName)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(context.state.subline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
            } compactLeading: {
                Text(context.state.icon)
            } compactTrailing: {
                Text(compactTrailingText(for: context.state))
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            } minimal: {
                Text(context.state.icon)
            }
            .widgetURL(deepLink(for: context))
            .keylineTint(WidgetBrand.gradientStart)
        }
    }

    /// Dynamic Islandの限られた面積では数字だけを見せ、状況説明は展開時に譲る。
    private func compactTrailingText(for state: EventActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .inProgress: return "\(state.photoCount)"
        case .newMemory, .ended: return "✨"
        }
    }

    private func deepLink(for context: ActivityViewContext<EventActivityAttributes>) -> URL? {
        guard let eventID = UUID(uuidString: context.attributes.eventID) else { return nil }
        return EventSnapDeepLink.url(for: .event(eventID: eventID))
    }
}

/// ロック画面のLive Activity。「最大限の存在感」を狙い、ブランド行と
/// 本文行を縦に積んで縦方向にもしっかり高さを使う(横1行に収める設計だと
/// 情報も文字サイズも小さいままになるため)。
private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<EventActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WidgetBrand.brandMark(dotSize: 7, textColor: .white.opacity(0.6))
                Spacer()
                Text(context.state.icon)
                    .font(.system(size: 26))
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.state.eventName)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(context.state.subline)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 8)

                shutterLink(eventIDString: context.attributes.eventID, size: 64)
            }
        }
        .padding(18)
        .activityBackgroundTint(WidgetBrand.activityBackground)
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - シャッターボタン(共通)

/// タップするとアプリのカメラ画面を直接開く。Live Activityはウィジェット同様
/// 実際の撮影処理を行わない(できない)ため、`Link`によるディープリンクで
/// アプリ側に画面遷移させるだけにする。`contentShape`で円全体を確実にタップ
/// 領域にする(アイコン部分だけがタップ判定になってしまう事故を避けるため)。
@ViewBuilder
private func shutterLink(eventIDString: String, size: CGFloat) -> some View {
    if let eventID = UUID(uuidString: eventIDString),
       let url = EventSnapDeepLink.url(for: .camera(eventID: eventID)) {
        Link(destination: url) {
            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(WidgetBrand.gradient, in: Circle())
                .contentShape(Circle())
        }
    }
}
