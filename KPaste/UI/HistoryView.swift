import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel
    private let thumbnailCache: ImageThumbnailCache

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        restorer: ClipRestorer,
        bulkPasteController: BulkPasteController,
        onRestored: @escaping () -> Void
    ) {
        thumbnailCache = ImageThumbnailCache(blobStorage: blobStorage)
        _viewModel = StateObject(
            wrappedValue: HistoryViewModel(
                repository: repository,
                blobStorage: blobStorage,
                restorer: restorer,
                bulkPasteController: bulkPasteController,
                onRestored: onRestored
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search clipboard history", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            content

            if viewModel.selectedCount > 0 {
                Divider()
                BulkPasteBar(viewModel: viewModel)
            }
        }
        .frame(
            minWidth: StatusItemController.popoverSize.width,
            minHeight: StatusItemController.popoverSize.height
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            EmptyStateView(
                title: "Couldn’t Load History",
                systemImage: "exclamationmark.triangle",
                description: errorMessage
            )
        } else if viewModel.pinned.isEmpty && viewModel.history.isEmpty {
            EmptyStateView(
                title: viewModel.searchText.isEmpty ? "No Clips Yet" : "No Results",
                systemImage: viewModel.searchText.isEmpty ? "clipboard" : "magnifyingglass",
                description: viewModel.searchText.isEmpty
                    ? "Copied items will appear here."
                    : "Try a different search."
            )
        } else {
            List {
                if !viewModel.pinned.isEmpty {
                    Section("Pinned") {
                        rows(viewModel.pinned)
                    }
                }

                if !viewModel.history.isEmpty {
                    Section("History") {
                        rows(viewModel.history)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func rows(_ clips: [ClipRecord]) -> some View {
        ForEach(clips) { clip in
            HStack(spacing: 6) {
                Button {
                    viewModel.restore(clip)
                } label: {
                    ClipRowView(clip: clip, thumbnailCache: thumbnailCache)
                }
                .buttonStyle(.plain)

                if viewModel.canBulkSelect(clip) {
                    Button {
                        viewModel.toggleSelection(clip)
                    } label: {
                        if let index = viewModel.selectionIndex(for: clip) {
                            Text("\(index)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Add to bulk paste")
                }
            }
            .contextMenu {
                Button(clip.pinned ? "Unpin" : "Pin") {
                    viewModel.togglePinned(clip)
                }
                Button("Delete", role: .destructive) {
                    viewModel.delete(clip)
                }
            }
        }
    }
}

private struct BulkPasteBar: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(viewModel.selectedCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    viewModel.clearSelection()
                }
                .buttonStyle(.link)
            }

            HStack(spacing: 8) {
                Picker("Separator", selection: $viewModel.separatorOption) {
                    ForEach(BulkSeparatorOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 125)

                if viewModel.separatorOption == .custom {
                    TextField("Custom", text: $viewModel.customSeparator)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Spacer()
                }

                Button("Paste") {
                    viewModel.pasteSelection()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(10)
        .background(.bar)
    }
}

private struct EmptyStateView: View {
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

private struct ClipRowView: View {
    let clip: ClipRecord
    let thumbnailCache: ImageThumbnailCache

    var body: some View {
        HStack(spacing: 10) {
            if clip.type == ClipContentType.image.rawValue, let id = clip.id {
                ImageThumbnailView(clipID: id, cache: thumbnailCache)
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.previewText.isEmpty ? "Untitled clip" : clip.previewText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(clip.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch ClipContentType(rawValue: clip.type) {
        case .text: "text.alignleft"
        case .rtf: "doc.richtext"
        case .image: "photo"
        case .file: "doc"
        case .url: "link"
        case nil: "questionmark.square.dashed"
        }
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
        .frame(width: 42, height: 42)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: clipID) {
            image = try? await cache.thumbnail(for: clipID)
        }
    }
}
