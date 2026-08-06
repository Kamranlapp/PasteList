import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject private var viewModel: HistoryViewModel
    @State private var rowFrames: [Int64: CGRect] = [:]
    @State private var suppressRowActivation = false
    @State private var showsBulkPastePanel = false
    @State private var isCursorPanelPinned = false
    @State private var isCursorPanelResizeModeEnabled = false
    @State private var isSavedPanelVisible: Bool
    @State private var hoveredClipID: Int64?
    @ObservedObject private var selectionResetController: HistorySelectionResetController
    private let blobStorage: BlobStorage
    private let thumbnailCache: ImageThumbnailCache
    private let usesTransparentBackground: Bool
    private let onCursorPanelPinChanged: (Bool) -> Void
    private let onCursorPanelResizeModeChanged: (Bool) -> Void
    private let onCursorPanelFilterMenuPresentationChanged: (Bool) -> Void
    private let onCursorPanelClearConfirmationChanged: (Bool) -> Void
    private let onSavedPanelVisibilityChanged: (Bool) -> Void
    private let onImagePreviewChanged: (Int64?) -> Void
    private static let listCoordinateSpace = "KPasteHistoryList"
    private static let imagePreviewHoverDelay = Duration.milliseconds(500)

    init(
        viewModel: HistoryViewModel,
        blobStorage: BlobStorage,
        thumbnailCache: ImageThumbnailCache,
        usesTransparentBackground: Bool = false,
        isSavedPanelVisible: Bool = false,
        onCursorPanelPinChanged: @escaping (Bool) -> Void = { _ in },
        onCursorPanelResizeModeChanged: @escaping (Bool) -> Void = { _ in },
        onCursorPanelFilterMenuPresentationChanged: @escaping (Bool) -> Void = { _ in },
        onCursorPanelClearConfirmationChanged: @escaping (Bool) -> Void = { _ in },
        onSavedPanelVisibilityChanged: @escaping (Bool) -> Void = { _ in },
        onImagePreviewChanged: @escaping (Int64?) -> Void = { _ in },
        selectionResetController: HistorySelectionResetController
    ) {
        self.viewModel = viewModel
        self.blobStorage = blobStorage
        self.thumbnailCache = thumbnailCache
        self.usesTransparentBackground = usesTransparentBackground
        _isSavedPanelVisible = State(initialValue: isSavedPanelVisible)
        self.onCursorPanelPinChanged = onCursorPanelPinChanged
        self.onCursorPanelResizeModeChanged = onCursorPanelResizeModeChanged
        self.onCursorPanelFilterMenuPresentationChanged = onCursorPanelFilterMenuPresentationChanged
        self.onCursorPanelClearConfirmationChanged = onCursorPanelClearConfirmationChanged
        self.onSavedPanelVisibilityChanged = onSavedPanelVisibilityChanged
        self.onImagePreviewChanged = onImagePreviewChanged
        self.selectionResetController = selectionResetController
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack(
                alignment: .leading,
                spacing: usesTransparentBackground
                    ? StatusItemController.cursorWindowControlSpacing
                    : 0
            ) {
                if usesTransparentBackground {
                    Color.clear
                        .frame(width: 152, height: StatusItemController.cursorWindowControlAreaHeight)
                        .padding(
                            .leading,
                            StatusItemController.cursorScrollBarWidth
                                + StatusItemController.cursorScrollBarSpacing
                        )
                }

                HStack(spacing: usesTransparentBackground ? 8 : 0) {
                    if usesTransparentBackground {
                        HistoryTickScrollIndicator(
                            itemCount: orderedClips.count,
                            activeItemIndex: firstVisibleClipIndex,
                            scrollToItem: { itemIndex in
                                guard orderedClips.indices.contains(itemIndex) else {
                                    return
                                }
                                withAnimation(.easeOut(duration: 0.16)) {
                                    scrollProxy.scrollTo(
                                        orderedClips[itemIndex].id,
                                        anchor: .center
                                    )
                                }
                            }
                        )
                    }

                    panelSurface

                    if usesTransparentBackground {
                        BulkPasteIconRail { format in
                            viewModel.pasteSelection(format: format)
                        }
                        .frame(
                            width: StatusItemController.cursorBulkPasteRailWidth,
                            alignment: .leading
                        )
                        .opacity(
                            showsBulkPastePanel && viewModel.selectedCount > 1
                                ? 1
                                : 0
                        )
                        .allowsHitTesting(
                            showsBulkPastePanel && viewModel.selectedCount > 1
                        )
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .trailing
            )
            .overlay(alignment: .topLeading) {
                if usesTransparentBackground {
                    CursorPanelControls(
                        isPinned: $isCursorPanelPinned,
                        isResizeModeEnabled: $isCursorPanelResizeModeEnabled,
                        isSavedPanelVisible: $isSavedPanelVisible,
                        pastesAsPlainText: $viewModel.pastesAsPlainText,
                        filter: $viewModel.filter,
                        pinChanged: onCursorPanelPinChanged,
                        resizeModeChanged: onCursorPanelResizeModeChanged,
                        savedPanelVisibilityChanged: onSavedPanelVisibilityChanged,
                        clearHistory: viewModel.clearHistory,
                        filterMenuPresentationChanged: onCursorPanelFilterMenuPresentationChanged,
                        clearConfirmationChanged: onCursorPanelClearConfirmationChanged
                    )
                }
            }
        }
    }

    private var panelSurface: some View {
        mainWindow
            .padding(usesTransparentBackground ? StatusItemController.cursorPanelPadding : 0)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background {
                if usesTransparentBackground {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .blur(radius: 15)
                        Color.black.opacity(0.2)
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: usesTransparentBackground ? 25 : 0,
                    style: .continuous
                )
            )
            .overlay(alignment: .bottomTrailing) {
                if usesTransparentBackground && isCursorPanelResizeModeEnabled {
                    CursorPanelResizeControl()
                        .padding(6)
                }
            }
        .onChange(of: viewModel.selectedCount) { selectedCount in
            if selectedCount < 2 {
                showsBulkPastePanel = false
            } else if !suppressRowActivation {
                showsBulkPastePanel = true
                hoveredClipID = nil
            }
            }
            .onChange(of: selectionResetController.token) { _ in
                resetSelectionState()
            }
            .task(id: hoveredClipID) {
                await updateImagePreview()
            }
    }

    /// Shows the hover preview only once the pointer has rested on an image row.
    /// SwiftUI cancels and restarts this task whenever `hoveredClipID` changes,
    /// so leaving a row hides the preview without any manual bookkeeping.
    private func updateImagePreview() async {
        guard
            let clipID = hoveredClipID,
            let clip = orderedClips.first(where: { $0.id == clipID }),
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

    private var mainWindow: some View {
        ZStack {
            VStack(spacing: 0) {
                content

                TextField("Search clipboard history", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }

            if showsBulkPastePanel && viewModel.selectedCount > 1 {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.pasteSelectionWithSpaces()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        } else if viewModel.history.isEmpty {
            EmptyStateView(
                title: viewModel.searchText.isEmpty ? "No Clips Yet" : "No Results",
                systemImage: viewModel.searchText.isEmpty ? "clipboard" : "magnifyingglass",
                description: viewModel.searchText.isEmpty
                    ? "Copied items will appear here."
                    : "Try a different search."
            )
        } else {
            historyList
        }
    }

    private var historyList: some View {
        ScrollViewReader { scrollProxy in
            // Saved clips live in their own panel, so the list only shows history.
            List {
                Section {
                    rows(viewModel.history)
                }
            }
            .listStyle(.inset)
            .scrollIndicators(.hidden)
            .scrollContentBackground(usesTransparentBackground ? .hidden : .visible)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 12)

                    Color.black

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                }
            }
            .coordinateSpace(name: Self.listCoordinateSpace)
            .onPreferenceChange(ClipRowFramePreferenceKey.self) { frames in
                rowFrames = frames
            }
            .onChange(of: selectionResetController.token) { _ in
                DispatchQueue.main.async {
                    guard let topClipID = viewModel.history.first?.id else {
                        return
                    }
                    scrollProxy.scrollTo(topClipID, anchor: .top)
                }
            }
        }
    }

    private var orderedClips: [ClipRecord] {
        viewModel.history
    }

    private var firstVisibleClipIndex: Int {
        orderedClips.enumerated().first { _, clip in
            guard let id = clip.id, let frame = rowFrames[id] else {
                return false
            }
            return frame.maxY > 0
        }?.offset ?? 0
    }

    @ViewBuilder
    private func rows(_ clips: [ClipRecord]) -> some View {
        ForEach(clips) { clip in
            rowContent(for: clip)
            .background {
                if let id = clip.id {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ClipRowFramePreferenceKey.self,
                            value: [
                                id: proxy.frame(
                                    in: .named(Self.listCoordinateSpace)
                                ),
                            ]
                        )
                    }
                }
            }
            .listRowBackground(
                rowBackground(for: clip, in: clips)
            )
            .onHover { isInside in
                guard !showsBulkPastePanel else {
                    hoveredClipID = nil
                    return
                }
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isInside, let clipID = clip.id {
                        hoveredClipID = clipID
                    } else if let clipID = clip.id, hoveredClipID == clipID {
                        hoveredClipID = nil
                    }
                }
            }
            // Secondary click saves the clip outright — no menu step.
            .overlay {
                RightClickActionView {
                    viewModel.togglePinned(clip)
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(for clip: ClipRecord) -> some View {
        switch clip.primaryInteraction {
        case .textSelection:
            ZStack {
                ClipRowView(
                    clip: clip,
                    thumbnailCache: thumbnailCache
                )

                TextSelectionSourceView(
                    clip: clip,
                    onActivate: { viewModel.restore(clip) },
                    onSelectionChanged: handleTextSelection,
                    onSelectionFinished: finishTextSelection
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .fileDrag:
            if
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
                restoreButton(for: clip)
            }

        case .restoreOnly:
            restoreButton(for: clip)
        }
    }

    private func restoreButton(for clip: ClipRecord) -> some View {
        Button {
            guard !suppressRowActivation else {
                return
            }
            viewModel.restore(clip)
        } label: {
            ClipRowView(
                clip: clip,
                thumbnailCache: thumbnailCache
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowBackground(
        for clip: ClipRecord,
        in clips: [ClipRecord]
    ) -> some View {
        if
            let clipID = clip.id,
            let clipIndex = clips.firstIndex(where: { $0.id == clipID }),
            viewModel.selectedClipIDs.contains(clipID)
        {
            let hasSelectedRowAbove = clipIndex > clips.startIndex
                && clips[clipIndex - 1].id.map(viewModel.selectedClipIDs.contains) == true
            let hasSelectedRowBelow = clipIndex < clips.index(before: clips.endIndex)
                && clips[clipIndex + 1].id.map(viewModel.selectedClipIDs.contains) == true

            SelectionBackgroundShape(
                roundsTopCorners: !hasSelectedRowAbove,
                roundsBottomCorners: !hasSelectedRowBelow
            )
            .fill(Color.accentColor.opacity(0.18))
        } else if
            let clipID = clip.id,
            hoveredClipID == clipID,
            !showsBulkPastePanel
        {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        } else {
            Color.clear
        }
    }

    private func handleTextSelection(_ clips: [ClipRecord]) {
        suppressRowActivation = true
        showsBulkPastePanel = false
        hoveredClipID = nil
        viewModel.replaceSelection(with: clips)
    }

    private func finishTextSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            suppressRowActivation = false
            if viewModel.selectedCount > 1 {
                showsBulkPastePanel = true
            } else {
                viewModel.clearSelection()
            }
        }
    }

    private func resetSelectionState() {
        suppressRowActivation = false
        showsBulkPastePanel = false
        isCursorPanelResizeModeEnabled = false
        hoveredClipID = nil
        onImagePreviewChanged(nil)
        viewModel.clearSelection()
    }
}
