import SwiftUI

struct CompanyStatusBadge: View {
    let status: CompanyStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: .capsule)
    }

    private var color: Color {
        switch status {
        case .considering: .orange
        case .active: .accentColor
        case .offer: .green
        case .rejected: .red
        case .withdrawn: .secondary
        }
    }
}

struct CompanyStatusField: View {
    let status: CompanyStatus

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("ステータス").fixedSize()
                Spacer(minLength: 12)
                CompanyStatusBadge(status: status).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ステータス")
                CompanyStatusBadge(status: status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
