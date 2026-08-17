//
//  EventSnapWidget.swift
//  EventSnapWidget
//
//  Small/Medium/Large ホーム画面Widget。
//
//  **やらないこと**: CloudKit同期、写真解析、大量の画像取得。ここで読むのは
//  `EventSnapSharedState`(メインアプリがApp Group内に書き込んだ、既に同期済みの
//  状態)と、最新Event Reelの縮小プレビュー1枚だけ。Widget自身は完全に受動的。
//

import SwiftUI
import WidgetKit

struct EventSnapWidgetEntry: TimelineEntry {
    let date: Date
    let state: EventSnapSharedState.State
    let previewImage: UIImage?
}

struct EventSnapWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EventSnapWidgetEntry {
        EventSnapWidgetEntry(date: Date(), state: .empty, previewImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (EventSnapWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EventSnapWidgetEntry>) -> Void) {
        // 状態が変わるたびにメインアプリが`WidgetCenter.reloadTimelines`を呼ぶ設計
        // (`EventSnapSharedState`参照)。Widget自身が定期的にポーリングする必要は
        // 無いため、単一エントリ+`.never`にして無駄な再計算を避ける。
        let timeline = Timeline(entries: [currentEntry()], policy: .never)
        completion(timeline)
    }

    private func currentEntry() -> EventSnapWidgetEntry {
        EventSnapWidgetEntry(
            date: Date(),
            state: EventSnapSharedState.load(),
            previewImage: EventSnapSharedState.latestReelPreviewImage()
        )
    }
}

struct EventSnapWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EventSnapWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
        .widgetURL(EventSnapDeepLink.url(for: entry.state))
    }
}

// MARK: - Small

private struct SmallWidgetView: View {
    let entry: EventSnapWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetBrand.brandMark()

            Spacer(minLength: 4)

            if entry.state.eventState == .ended, entry.state.latestReelID != nil {
                Text("✨ MEMORY READY")
                    .font(.caption2.bold())
                    .foregroundStyle(WidgetBrand.gradientStart)
                Text(entry.state.eventName ?? "")
                    .font(.headline)
                    .lineLimit(2)
                Text("Event Reel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let name = entry.state.eventName {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 2)
                Text(statsLine(participantCount: entry.state.participantCount, photoCount: entry.state.photoCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("EventSnap")
                    .font(.headline)
                Text("イベントに参加すると\nここに表示されます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(WidgetBrand.background, for: .widget)
    }
}

// MARK: - Medium

private struct MediumWidgetView: View {
    let entry: EventSnapWidgetEntry

    var body: some View {
        HStack(spacing: 14) {
            previewThumbnail

            VStack(alignment: .leading, spacing: 6) {
                WidgetBrand.brandMark()

                Text(entry.state.eventName ?? "EventSnap")
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 2)

                if entry.state.latestReelID != nil {
                    Text(entry.state.eventState == .ended ? "✨ MEMORY READY" : "新しい思い出ができました")
                        .font(.caption)
                        .foregroundStyle(entry.state.eventState == .ended ? WidgetBrand.gradientStart : .secondary)
                }

                Text(statsLine(participantCount: entry.state.participantCount, photoCount: entry.state.photoCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WidgetBrand.background, for: .widget)
    }

    @ViewBuilder
    private var previewThumbnail: some View {
        if let image = entry.previewImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

// MARK: - Large

private struct LargeWidgetView: View {
    let entry: EventSnapWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetBrand.brandMark()

            previewImageArea

            Text(entry.state.eventName ?? "EventSnap")
                .font(.title3.bold())
                .lineLimit(2)

            Text(statsLine(participantCount: entry.state.participantCount, photoCount: entry.state.photoCount))
                .font(.caption)
                .foregroundStyle(.secondary)

            if entry.state.timeCapsuleLockedCount > 0 {
                Text("\(entry.state.timeCapsuleLockedCount)枚の思い出がまだ眠っています")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.state.latestReelID != nil {
                Text(entry.state.eventState == .ended ? "✨ MEMORY READY" : "✨ NEW MEMORY")
                    .font(.caption.bold())
                    .foregroundStyle(WidgetBrand.gradientStart)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(WidgetBrand.background, for: .widget)
    }

    @ViewBuilder
    private var previewImageArea: some View {
        if let image = entry.previewImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .overlay(Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary))
        }
    }
}

// MARK: - 共通の文言整形

/// 「1 PEOPLE」のような不自然な英語を避け、単数/複数を正しく出し分ける
/// (`SocialCardService.MultiPhotoRenderer.statsLine`と同じ考え方)。
private func statsLine(participantCount: Int, photoCount: Int) -> String {
    let people = max(participantCount, 1)
    let photos = max(photoCount, 1)
    let peopleWord = people == 1 ? "PERSON" : "PEOPLE"
    let photoWord = photos == 1 ? "PHOTO" : "PHOTOS"
    return "\(photos) \(photoWord) · \(people) \(peopleWord)"
}

struct EventSnapWidget: Widget {
    let kind = "EventSnapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EventSnapWidgetProvider()) { entry in
            EventSnapWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("EventSnap")
        .description("今のイベントの状態と、最新のEvent Reelを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
