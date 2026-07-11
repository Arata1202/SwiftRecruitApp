import SwiftUI

struct CompanyStatusBadge: View {
    let status: CompanyStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: .capsule)
    }

    private var color: Color {
        switch status {
        case .considering: .secondary
        case .active: .accentColor
        case .offer: .green
        case .rejected: .secondary
        case .withdrawn: .orange
        }
    }
}
