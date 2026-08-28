//
//  EventSwitcherView.swift
//  EventSnap
//
//  参加済みイベントの切り替え・新規作成
//

import SwiftUI

/// 複数のグループを行き来するための画面。
///
/// これまでは一度に1つのイベントしか持てず、別のイベントに参加すると
/// 前のイベントに戻れなくなっていた。参加履歴を端末に持たせることで
/// 好きなときに切り替えられるようにする。
///
/// 「現在（開催中）」と「過去（終了済み）」を分けて表示する。終了したイベントを
/// 参加中の一覧にいつまでも残すと、使うほどに一覧が伸びて分かりにくくなるため。
/// ただし履歴からは消さない（`EventRepository`が保持する参加履歴自体は変えない）。
struct EventSwitcherView: View {
    @ObservedObject var eventViewModel: EventViewModel
    @Environment(\.dismiss) private var dismiss

    /// いま出しているシート。HomeViewと同じ理由で、`.sheet`を2つ重ねずに
    /// 1つの状態へ束ねている（同時に2枚出そうとすると片方が無視される）。
    @State private var activeSheet: SwitcherSheet?
    @State private var newEventName = ""
    @State private var leaveTarget: Event?

    /// シートが閉じきったあとに作成するイベント名。`nil` なら作成待ちは無い。
    @State private var pendingEventName: String?

    private enum SwitcherSheet: String, Identifiable {
        case join
        case create

        var id: String { rawValue }
    }

    private var currentEvents: [Event] {
        eventViewModel.recentEvents.filter(\.isActive)
    }

    private var pastEvents: [Event] {
        eventViewModel.recentEvents.filter { !$0.isActive }
    }

    var body: some View {
        NavigationView {
            List {
                if eventViewModel.recentEvents.isEmpty {
                    Text("参加中のイベントはありません")
                        .foregroundColor(.secondary)
                } else {
                    if !currentEvents.isEmpty {
                        Section("現在") {
                            ForEach(currentEvents) { event in
                                row(for: event)
                            }
                        }
                    }

                    if !pastEvents.isEmpty {
                        Section("過去のイベント") {
                            ForEach(pastEvents) { event in
                                row(for: event)
                            }
                        }
                    }
                }

                // 「作成」と「参加」を明確に分けた導線。
                // 以前はここに参加（QRコード）しか無かった。
                Section {
                    Button {
                        activeSheet = .create
                    } label: {
                        Label("イベントを作成", systemImage: "plus.circle")
                    }

                    Button {
                        activeSheet = .join
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
            .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
                switch sheet {
                case .join:
                    QRScannerView(eventViewModel: eventViewModel)
                case .create:
                    // 既存のEventCreationSheet（HomeView.swift）をそのまま再利用する。
                    // 作成すると EventRepository が currentEvent を新しいイベントに
                    // 切り替えるので、このスイッチャー自体を閉じれば、下にある
                    // MainTabViewが自動的に新しいイベントの中身を表示する。
                    //
                    // ここでも作成はシートが閉じきってから行う。シートの開閉と
                    // 画面の入れ替えが重なると、提示が取りこぼされることがある
                    // （HomeView.handleSheetDismiss のコメントを参照）。
                    EventCreationSheet(eventName: $newEventName) { name in
                        pendingEventName = name
                    }
                }
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
        // iPadでは NavigationView が既定で2カラムの分割表示になり、
        // 中身がサイドバー側に押し込まれて見えなくなるため、スタック表示に固定する。
        .navigationViewStyle(.stack)
        .task { await eventViewModel.loadRecentEvents() }
    }

    /// シートが完全に閉じてからイベントを作成する。
    /// 理由は `HomeView.handleSheetDismiss` のコメントを参照。
    private func handleSheetDismiss() {
        guard let name = pendingEventName else { return }
        pendingEventName = nil
        Task {
            await eventViewModel.createEvent(name: name)
            newEventName = ""
            dismiss()
        }
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
                // 単一選択（タップで即座に切り替わる）ことが伝わるよう、
                // 選択中の行だけチェックマークを出す。未選択行には「空丸」を
                // 置かない（複数選択可能なチェックリストに見えるのを避けるため）。
                // 選択有無で行の左端が揃わなくならないよう、非選択行では
                // 同じ大きさのアイコンを透明にして場所だけ確保する。
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(isCurrent ? .blue : .clear)

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
