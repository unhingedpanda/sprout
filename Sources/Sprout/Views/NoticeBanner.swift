import SwiftUI

/// A passing message over the bottom of the list: what just happened, not an error.
/// It stays eight seconds, or until dismissed, and never takes focus.
struct NoticeBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let notice = model.notice {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        Text(notice.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark") { model.notice = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 560)
                .glassEffect(in: .rect(cornerRadius: 16))
                .padding(16)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .task(id: notice.id) {
                    AccessibilityNotification.Announcement(notice.title).post()
                    try? await Task.sleep(for: .seconds(8))
                    if model.notice?.id == notice.id { model.notice = nil }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.notice)
    }
}
