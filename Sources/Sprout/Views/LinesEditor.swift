import SwiftUI

/// A text area for lists typed one entry per line. A single-line TextField treats Return as
/// "submit", which closed sheets or dropped lines; here Return starts a new line as people expect.
struct LinesEditor: View {
    @Binding var text: String
    var placeholder = ""
    var minHeight: CGFloat = 64

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !placeholder.isEmpty {
                    Text(verbatim: placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The title at the top of a sheet. Sheets on macOS show no title bar, and a `navigationTitle`
/// on a sheet renames the main window instead, so each sheet says what it is here.
struct SheetHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .accessibilityAddTraits(.isHeader)
    }
}
