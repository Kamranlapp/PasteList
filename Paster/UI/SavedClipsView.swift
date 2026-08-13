import AppKit
import SwiftUI

/// Contents of the Saved panel. Deliberately simpler than `HistoryView`: no
/// search field, no tick scroll bar and no bulk selection — this is a short
/// curated list where one click pastes.
struct SavedClipsView: View {
    @ObservedObject private var viewModel: HistoryViewModel
    @State private var hoveredClipID: Int64?
    private let blobStorage: BlobStorage
    private let thumbnailCache: ImageThumbnailCache
    private let onImagePreviewChanged: (Int64?) -> Void
    private static let imagePreviewHoverDelay = Duration.milliseconds(500)

    init(
        viewModel: HistoryViewModel,
        blobStorage: BlobStorage,
        thumbnailCache: ImageThumbnailCache,
        onImagePreviewChanged: @escaping (Int64?) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.blobStorage = blobStorage
        self.thumbnailCache = thumbnailCache
        self.onImagePreviewChanged = onImagePreviewChanged
    }

    var body: some View {
        content
            .padding(StatusItemController.cursorPanelPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .blur(radius: 15)
                    // A touch lighter than the history panel so the two windows
                    // read as different surfaces.
                    Color.white.opacity(0.1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .task(id: hoveredClipID) {
                await updateImagePreview()
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.pinned.isEmpty {
            EmptyStateView(
                title: "Nothing Saved",
                systemImage: "square.and.arrow.down",
                description: "Right-click a clip and choose Save."
            )
        } else {
            savedList
        }
    }

    private var savedList: some View {
        List {
            Section {
                ForEach(viewModel.pinned) { clip in
                    rowContent(for: clip)
                        .listRowBackground(rowBackground(for: clip))
                        .onHover { isInside in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                if isInside, let clipID = clip.id {
                                    hoveredClipID = clipID
                                } else if let clipID = clip.id, hoveredClipID == clipID {
                                    hoveredClipID = nil
                                }
                            }
                        }
                        // Secondary click removes the clip from Saved and sends
                        // it back to the top of the history.
                        .overlay {
                            RightClickActionView {
                                viewModel.togglePinned(clip)
                            }
                        }
                }
            }
        }
        .listStyle(.inset)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowContent(for clip: ClipRecord) -> some View {
        if
            clip.primaryInteraction == .fileDrag,
            let urls = try? blobStorage.dragURLs(for: clip),
            !urls.isEmpty
        {
            ZStack {
                ClipRowView(
                    clip: clip,
                    thumbnailCache: thumbnailCache,
                    fileURLs: urls
                )

                FileDragSourceView(
                    urls: urls,
                    onActivate: { viewModel.restore(clip) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Button {
                viewModel.restore(clip)
            } label: {
                ClipRowView(clip: clip, thumbnailCache: thumbnailCache)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowBackground(for clip: ClipRecord) -> some View {
        if let clipID = clip.id, hoveredClipID == clipID {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        } else {
            Color.clear
        }
    }

    private func updateImagePreview() async {
        guard
            let clipID = hoveredClipID,
            let clip = viewModel.pinned.first(where: { $0.id == clipID }),
            ClipContentType(rawValue: clip.type) == .image
        else {
            onImagePreviewChanged(nil)
            return
        }
        try? await Task.sleep(for: Self.imagePreviewHoverDelay)
        guard !Task.isCancelled else {
            return
        }
        onImagePreviewChanged(clipID)
    }
}
