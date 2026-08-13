import AppKit
import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipRowView: View {
    let clip: ClipRecord
    let thumbnailCache: ImageThumbnailCache
    var fileURLs: [URL] = []
    var quickPasteKey: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let quickPasteKey {
                Text(quickPasteKey)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .accessibilityLabel("Quick paste key \(quickPasteKey)")
            }

            HStack(spacing: 6) {
                Text(clip.previewText.isEmpty ? "Untitled clip" : clip.previewText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            trailingIcon
                .fixedSize(horizontal: true, vertical: false)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let timestamp = ClipTimestampFormatter.components(
                    for: clip.createdAt,
                    relativeTo: context.date
                )
                VStack(alignment: .trailing, spacing: 3) {
                    Text(timestamp.day)
                    Text(timestamp.time)
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 3)
        // Keep glyph overhang away from the List row's clipping boundary.
        // This is especially visible on the final digit in times such as 14:50.
        .padding(.trailing, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingIcon: some View {
        switch ClipContentType(rawValue: clip.type) {
        case .image:
            if let id = clip.id {
                ImageThumbnailView(clipID: id, cache: thumbnailCache)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        case .file:
            if let fileURL = fileURLs.first {
                FileIconView(url: fileURL)
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        case .text, .rtf, .url, nil:
            EmptyView()
        }
    }
}

struct MouseSwipeDeleteRow<Content: View>: View {
    let offset: CGFloat
    @ViewBuilder let content: () -> Content

    private var revealWidth: CGFloat {
        min(max(-offset, 0), MouseSwipeDeleteGesture.maximumRevealDistance)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                HStack(spacing: 5) {
                    Image(systemName: "trash.fill")
                    if revealWidth >= 70 {
                        Text("Delete")
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red)
                .accessibilityHidden(true)
            }

            content()
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ImageThumbnailView: View {
    let clipID: Int64
    let cache: ImageThumbnailCache

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: clipID) {
            image = try? await cache.thumbnail(for: clipID)
        }
    }
}

private struct FileIconView: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
    }
}

enum ClipTimestampFormatter {
    struct Components: Equatable {
        let day: String
        let time: String
    }

    static func components(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> Components {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            day = "Yesterday"
        } else {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
            weekdayFormatter.timeZone = calendar.timeZone
            weekdayFormatter.dateFormat = "EEEE"
            day = weekdayFormatter.string(from: date)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        return Components(day: day, time: timeFormatter.string(from: date))
    }

    static func string(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let value = components(for: date, relativeTo: now, calendar: calendar)
        return "\(value.day) \(value.time)"
    }
}
