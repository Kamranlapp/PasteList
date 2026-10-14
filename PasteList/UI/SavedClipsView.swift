import AppKit
import SwiftUI

/// Contents of the Saved panel. Deliberately simpler than `HistoryView`: no
/// search field, no tick scroll bar and no bulk selection — this is a short
/// curated list where one click pastes.
struct SavedClipsView: View {
    @ObservedObject private var viewModel: HistoryViewModel
    @State private var hoveredClipID: Int64?
    @State private var hoverUpdateGeneration = 0
    @State private var rowWidths: [Int64: CGFloat] = [:]
    @State private var mouseSwipeOffsets: [Int64: CGFloat] = [:]
    private let blobStorage: BlobStorage
    private let thumbnailCache: ImageThumbnailCache
    private let onActivateClip: (ClipRecord) -> Void
    private let onPreviewChanged: (ClipPreviewTarget?) -> Void
    private static let imagePreviewHoverDelay = Duration.milliseconds(500)

    init(
        viewModel: HistoryViewModel,
        blobStorage: BlobStorage,
        thumbnailCache: ImageThumbnailCache,
        onActivateClip: @escaping (ClipRecord) -> Void,
        onPreviewChanged: @escaping (ClipPreviewTarget?) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.blobStorage = blobStorage
        self.thumbnailCache = thumbnailCache
        self.onActivateClip = onActivateClip
        self.onPreviewChanged = onPreviewChanged
    }

    var body: some View {
        content
            .padding(CursorPanelStyle.contentPadding)
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
            .clipShape(
                RoundedRectangle(cornerRadius: CursorPanelStyle.cornerRadius, style: .continuous)
            )
            .task(id: hoveredClipID) {
                await updatePreview()
            }
            .onDisappear {
                onPreviewChanged(nil)
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
                ForEach(Array(viewModel.pinned.enumerated()), id: \.element.id) { index, clip in
                    let isHighlighted = isHoverHighlightVisible(for: clip)
                    let nextIsHighlighted = viewModel.pinned.indices.contains(index + 1)
                        && isHoverHighlightVisible(for: viewModel.pinned[index + 1])
                    ClipListRow(
                        isHighlighted: isHighlighted,
                        showsSeparator: index < viewModel.pinned.count - 1
                            && !isHighlighted
                            && !nextIsHighlighted
                    ) {
                        MouseSwipeDeleteRow(offset: mouseSwipeOffset(for: clip)) {
                            rowContent(for: clip)
                        }
                    }
                        .listRowBackground(rowBackground(for: clip))
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .onHover { isInside in
                            scheduleHoverUpdate(
                                for: clip.id,
                                isInside: isInside
                            )
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
        .compactVerticalListMargins()
        .environment(\.defaultMinListRowHeight, ClipRowStyle.height)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(RowSnappingScrollObserver(rowHeight: ClipRowStyle.scrollPitch))
        .mask {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: CursorPanelStyle.listMaskHeight)
                Color.black
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.45),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: CursorPanelStyle.listMaskHeight)
            }
        }
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
                    fileURLs: urls,
                    onWidthChanged: { updateRowWidth($0, for: clip) }
                )

                FileDragSourceView(
                    urls: urls,
                    onActivate: { onActivateClip(clip) },
                    onDelete: { commitMouseSwipeDelete(clip) },
                    onSwipeChanged: { updateMouseSwipe($0, for: clip) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ZStack {
                ClipRowView(
                    clip: clip,
                    thumbnailCache: thumbnailCache,
                    onWidthChanged: { updateRowWidth($0, for: clip) }
                )

                MouseSwipeActionView(
                    onActivate: { onActivateClip(clip) },
                    onDelete: { commitMouseSwipeDelete(clip) },
                    onSwipeChanged: { updateMouseSwipe($0, for: clip) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func mouseSwipeOffset(for clip: ClipRecord) -> CGFloat {
        clip.id.flatMap { mouseSwipeOffsets[$0] } ?? 0
    }

    private func updateMouseSwipe(_ translation: CGFloat, for clip: ClipRecord) {
        guard let id = clip.id else {
            return
        }
        let clampedOffset = MouseSwipeDeleteGesture.visualOffset(for: translation)
        if clampedOffset == 0 {
            withAnimation(.easeOut(duration: 0.18)) {
                mouseSwipeOffsets[id] = nil
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mouseSwipeOffsets[id] = clampedOffset
            }
        }
    }

    private func commitMouseSwipeDelete(_ clip: ClipRecord) {
        guard let id = clip.id else {
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            mouseSwipeOffsets[id] = -400
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            mouseSwipeOffsets[id] = nil
            viewModel.delete(clip)
        }
    }

    @ViewBuilder
    private func rowBackground(for clip: ClipRecord) -> some View {
        Color.clear
    }

    private func isHoverHighlightVisible(for clip: ClipRecord) -> Bool {
        guard let clipID = clip.id, hoveredClipID == clipID else {
            return false
        }
        return true
    }

    private func scheduleHoverUpdate(for clipID: Int64?, isInside: Bool) {
        hoverUpdateGeneration &+= 1
        let generation = hoverUpdateGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard generation == hoverUpdateGeneration else {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                if isInside, let clipID {
                    hoveredClipID = clipID
                } else if let clipID, hoveredClipID == clipID {
                    hoveredClipID = nil
                }
            }
        }
    }

    private func updatePreview() async {
        guard
            let clipID = hoveredClipID,
            let clip = viewModel.pinned.first(where: { $0.id == clipID })
        else {
            onPreviewChanged(nil)
            return
        }
        try? await Task.sleep(for: Self.imagePreviewHoverDelay)
        guard !Task.isCancelled else {
            return
        }
        if ClipContentType(rawValue: clip.type) == .image {
            onPreviewChanged(.image(clipID))
        } else if let rowWidth = rowWidths[clipID], ClipTextPreviewPolicy.shouldShow(
            for: clip,
            rowWidth: rowWidth,
            hasQuickPasteKey: false
        ) {
            onPreviewChanged(.text(clipID))
        } else {
            onPreviewChanged(nil)
        }
    }

    private func updateRowWidth(_ width: CGFloat, for clip: ClipRecord) {
        guard let id = clip.id, rowWidths[id] != width else {
            return
        }
        rowWidths[id] = width
    }

}
