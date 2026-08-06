//
//  EventSwitcherView.swift
//  EventSnap
//
//  参加済みイベントの切り替え
//

import SwiftUI

/// 複数のグループを行き来するための画面。
///
/// これまでは一度に1つのイベントしか持てず、別のイベントに参加すると
/// 前のイベントに戻れなくなっていた。参加履歴を端末に持たせることで
/// 好きなときに切り替えられるようにする。
struct EventSwitcherView: View {
    @ObservedObject var eventViewModel: EventViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showJoinSheet = false
    @State private var leaveTarget: Event?

    var body: some View {
        NavigationView {
            List {
                if eventViewModel.recentEvents.isEmpty {
                    Text("参加中のイベントはありません")
                        .foregroundColor(.secondary)
                } else {
                    Section("参加中のイベント") {
                        ForEach(eventViewModel.recentEvents) { event in
                            row(for: event)
                        }
                    }
                }

                Section {
                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("QRコードで参加", systemImage: "qrcode.viewfinder")
                    }
                } footer: {
                    // 参加経路をQRコードに限ることで「その場にいた人だけの集まり」を保つ
                    Text("参加できるのは、主催者のQRコードをその場で読み取った人だけです。別のイベントに参加しても、今のイベントの写真は消えません。")
                }
            }
            .navigationTitle("イベントを切り替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .refreshable { await eventViewModel.loadRecentEvents() }
            .sheet(isPresented: $showJoinSheet) {
                QRScannerView(eventViewModel: eventViewModel)
            }
            .confirmationDialog(
                "「\(leaveTarget?.name ?? "")」を一覧から外しますか？",
                isPresented: Binding(get: { leaveTarget != nil },
                                     set: { if !$0 { leaveTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("一覧から外す", role: .destructive) {
                    if let event = leaveTarget {
                        Task { await eventViewModel.leaveEvent(event) }
                    }
                    leaveTarget = nil
                }
                Button("キャンセル", role: .cancel) { leaveTarget = nil }
            } message: {
                Text("イベント自体は削除されません。QRコードをもう一度読み取れば、また参加できます。")
            }
        }
        .task { await eventViewModel.loadRecentEvents() }
    }

    private func row(for event: Event) -> some View {
        let isCurrent = event.id == eventViewModel.currentEvent?.id

        return Button {
            guard !isCurrent else { dismiss(); return }
            Task {
                await eventViewModel.switchEvent(to: event)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isCurrent ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name)
                        .foregroundColor(.primary)
                        .fontWeight(isCurrent ? .semibold : .regular)

                    HStack(spacing: 10) {
                        Text("\(event.participantIDs.count)人")
                        Text(event.createdAt.formatted(date: .abbreviated, time: .omitted))
                        if !event.isActive {
                            Text("終了")
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.18))
                                .cornerRadius(4)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                leaveTarget = event
            } label: {
                Label("外す", systemImage: "minus.circle")
            }
        }
    }
}
