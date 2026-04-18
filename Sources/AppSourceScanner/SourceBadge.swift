import SwiftUI

struct SourceBadge: View {
    let source: AppSource

    var body: some View {
        Text(source.rawValue)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.12))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch source {
        case .homebrew: return .orange
        case .appStore: return .blue
        case .manual: return .gray
        }
    }
}
