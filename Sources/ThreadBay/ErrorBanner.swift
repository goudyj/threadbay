import SwiftUI

/// Inline error shown inside sheets, where the window-level alert cannot appear.
struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
