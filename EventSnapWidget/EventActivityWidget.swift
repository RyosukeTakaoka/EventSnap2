//
//  EventActivityWidget.swift
//  EventSnapWidget
//
//  Live Activity(Dynamic Island / ロック画面)のUI定義。
//  状態(EventActivityAttributes.ContentState)自体はメインアプリの
//  `EventActivityManager`が更新する。ここは表示を組み立てるだけ。
//
//  **配色の注意**: ロック画面(`activityBackgroundTint`)とDynamic Island(常に
//  システムの黒背景)は前提となる背景色が真逆。`.primary`/`.secondary`任せに
//  すると、`activityBackgroundTint`で明るい背景に変えても文字色が白いまま
//  残り「文字が見えなくなる」不具合が起きるため、両方とも常に明示的な色を指定する。
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
                        .font(.system(size: 30))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    shutterLink(eventIDString: context.attributes.eventID, size: 44)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.eventName)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(context.state.subline)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
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

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<EventActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Text(context.state.icon)
                .font(.system(size: 36))

            VStack(alignment: .leading, spacing: 4) {
                WidgetBrand.brandMark(dotSize: 6)
                Text(context.state.eventName)
                    .font(.title2.bold())
                    .foregroundStyle(WidgetBrand.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(context.state.subline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WidgetBrand.ink.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            shutterLink(eventIDString: context.attributes.eventID, size: 54)
        }
        .padding(16)
        .activityBackgroundTint(WidgetBrand.background)
        .activitySystemActionForegroundColor(WidgetBrand.ink)
    }
}

// MARK: - シャッターボタン(共通)

/// タップするとアプリのカメラ画面を直接開く。Live Activityはウィジェット同様
/// 実際の撮影処理を行わない(できない)ため、`Link`によるディープリンクで
/// アプリ側に画面遷移させるだけにする。
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
        }
    }
}
