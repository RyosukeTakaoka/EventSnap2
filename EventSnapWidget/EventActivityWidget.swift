//
//  EventActivityWidget.swift
//  EventSnapWidget
//
//  Live Activity(Dynamic Island / ロック画面)のUI定義。
//  状態(EventActivityAttributes.ContentState)自体はメインアプリの
//  `EventActivityManager`が更新する。ここは表示を組み立てるだけ。
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
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(compactTrailingText(for: context.state))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.eventName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text(context.state.icon)
            } compactTrailing: {
                Text(compactTrailingText(for: context.state))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Text(context.state.icon)
            }
            .widgetURL(deepLink(for: context))
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
        HStack(spacing: 12) {
            Text(context.state.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.eventName)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.subline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            WidgetBrand.brandMark(dotSize: 5)
        }
        .padding()
        .activityBackgroundTint(WidgetBrand.background)
        .activitySystemActionForegroundColor(WidgetBrand.ink)
    }
}
