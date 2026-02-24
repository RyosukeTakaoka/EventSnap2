//
//  FilterPickerView.swift
//  EventSnap
//
//  フィルター選択ビュー
//

import SwiftUI

struct FilterPickerView: View {
    @Binding var selectedFilter: CameraViewModel.FilterType
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // ハンドル
                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)

                Text("フィルターを選択")
                    .font(.headline)
                    .padding(.top, 8)

                // フィルター一覧
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(CameraViewModel.FilterType.allCases) { filter in
                            FilterCell(
                                filter: filter,
                                isSelected: selectedFilter == filter,
                                onTap: {
                                    selectedFilter = filter
                                    onDismiss()
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(20, corners: [.topLeft, .topRight])
        }
        .ignoresSafeArea()
    }
}

// MARK: - フィルターセル

struct FilterCell: View {
    let filter: CameraViewModel.FilterType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                        .frame(width: 60, height: 60)

                    Image(systemName: filter.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? .white : .primary)
                }

                Text(filter.rawValue)
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .primary)
            }
        }
    }
}

// MARK: - 角丸ヘルパー

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    FilterPickerView(
        selectedFilter: .constant(.beauty),
        onDismiss: {}
    )
}
