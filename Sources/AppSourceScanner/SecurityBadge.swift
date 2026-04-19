import SwiftUI

struct SecurityBadge: View {
    let status: SecurityStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 8))
            Text(status.rawValue)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.12))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch status {
        case .appStore: return "checkmark.seal.fill"
        case .signed: return "checkmark.shield.fill"
        case .adHoc: return "exclamationmark.triangle.fill"
        case .unsigned: return "xmark.shield.fill"
        case .notApplicable: return "minus"
        }
    }

    private var badgeColor: Color {
        switch status {
        case .appStore: return .blue
        case .signed: return .green
        case .adHoc: return .orange
        case .unsigned: return .red
        case .notApplicable: return .gray
        }
    }
}
