//
//  RelayView.swift
//  EventSnap
//
//  Relay（バトン形式の共同アルバム）の進行状況画面
//

import SwiftUI

struct RelayView: View {
    @StateObject private var viewModel = RelayViewModel()

    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if let session = viewModel.session {
                    RelayParticipantGridView(rows: viewModel.rows)

                    if !viewModel.canAddNewMoment {
                        endedBanner
                    } else if viewModel.isMyTurnOpen {
                        myTurnCard
                    } else if viewModel.isMyTurnComingSoon {
                        comingSoonBanner
                    }

                    NavigationLink {
                        RelayCompletionView(session: session, rows: viewModel.rows)
                    } label: {
                        Label("完成イメージを見る", systemImage: "square.grid.2x2")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 4)
                } else if viewModel.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    startCard
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(20)
        }
        .navigationTitle("Relay")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadSession() }
        .refreshable { await viewModel.loadSession() }
        .fullScreenCover(isPresented: $showCamera) {
            RelayTurnCameraView(viewModel: viewModel)
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        VStack(spacing: 8) {
            Text("Relay")
                .font(DesignTokens.heading(28))
            Text("参加者が順番に主役になって、Momentをつないでいく共同アルバム")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 開始前

    private var startCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.socialdance")
                .font(.system(size: 44))
                .foregroundStyle(DesignTokens.accentGradient)

            Text("まだRelayは始まっていません")
                .font(.headline)

            Text("参加者の順番はランダムに決まります。開始すると、最初の1人がすぐに撮影できるようになります。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.startRelay() }
            } label: {
                if viewModel.isStarting {
                    ProgressView().tint(.white)
                } else {
                    Text("Relayを始める")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.isStarting || !viewModel.canAddNewMoment)
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium, style: .continuous))
    }

    // MARK: - 自分の番

    private var myTurnCard: some View {
        VStack(spacing: 14) {
            Text("あなたの番が開放されました")
                .font(.headline)
            Text("Momentを撮影しましょう")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showCamera = true
            } label: {
                Text("撮影する")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(DesignTokens.accentGradient.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium, style: .continuous))
    }

    private var comingSoonBanner: some View {
        Label("もうすぐあなたの番です", systemImage: "sparkles")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DesignTokens.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DesignTokens.primary.opacity(0.12))
            .clipShape(Capsule())
    }

    private var endedBanner: some View {
        Label("このイベントは終了しています。新しいMomentは追加できません。", systemImage: "lock.fill")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

// MARK: - 進行状況グリッド

/// 参加者を横並びのグリッドで示す。撮影済み/今の主役/まだ、の3状態を色分けで表す。
/// 「締切超過」を思わせる赤色や失敗を想起させる表現は使わない。
struct RelayParticipantGridView: View {
    let rows: [RelayParticipantRow]

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RelayParticipantCell(row: row, order: index + 1)
            }
        }
    }
}

struct RelayParticipantCell: View {
    let row: RelayParticipantRow
    let order: Int

    private var initial: String {
        String(row.participant.deviceName.prefix(1))
    }

    private var fillStyle: AnyShapeStyle {
        switch row.slot.status {
        case .completed: return AnyShapeStyle(DesignTokens.primary)
        case .open: return AnyShapeStyle(DesignTokens.accentGradient)
        case .waiting: return AnyShapeStyle(Color(.systemGray5))
        }
    }

    private var statusLabel: String {
        switch row.slot.status {
        case .completed: return "撮影済み"
        case .open: return "今の主役"
        case .waiting: return "まだ"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(fillStyle)
                    .frame(width: 56, height: 56)

                if row.slot.status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text(initial)
                        .font(.headline)
                        .foregroundColor(row.slot.status == .open ? .white : .secondary)
                }

                if row.isSelf {
                    Circle()
                        .stroke(DesignTokens.secondary, lineWidth: 2)
                        .frame(width: 62, height: 62)
                }
            }

            Text(row.participant.deviceName)
                .font(.caption2)
                .lineLimit(1)
                .foregroundColor(.primary)

            Text(statusLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(width: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(order)番目、\(row.participant.deviceName)、\(statusLabel)")
    }
}

#Preview {
    NavigationView {
        RelayView()
    }
}
