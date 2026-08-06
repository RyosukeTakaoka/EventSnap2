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
                        Label("招待コードで参加", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("別のイベントに参加しても、今のイベントの写真は消えません。いつでもここから戻れます。")
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
                JoinByCodeView(eventViewModel: eventViewModel) {
                    showJoinSheet = false
                    dismiss()
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
                Text("イベント自体は削除されません。招待コードやQRコードから、また参加できます。")
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

// MARK: - 招待コードで参加

/// 6文字のコードを入力してイベントに参加する。
/// QRコードはその場にいる人にしか使えないので、離れた相手はこちらを使う。
struct JoinByCodeView: View {
    @ObservedObject var eventViewModel: EventViewModel
    var onJoined: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    private var normalized: String { InviteCode.normalize(code) }
    private var canSubmit: Bool { InviteCode.isValid(normalized) && !eventViewModel.isLoading }

    var body: some View {
        NavigationView {
            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    Text("招待コードを入力")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("イベントの主催者から教えてもらった\n6文字のコードを入力してください")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)

                TextField("ABC123", text: $code)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .padding(.horizontal, 32)
                    .onChange(of: code) { _, newValue in
                        // 6文字を超えて打てないようにする
                        let cleaned = InviteCode.normalize(newValue)
                        if cleaned.count > InviteCode.length {
                            code = String(cleaned.prefix(InviteCode.length))
                        }
                    }

                if let error = eventViewModel.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        await eventViewModel.joinEvent(inviteCode: normalized)
                        if eventViewModel.error == nil { onJoined() }
                    }
                } label: {
                    if eventViewModel.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("参加する").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit)
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}
