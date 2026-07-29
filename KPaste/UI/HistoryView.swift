import AppKit
import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel
    @State private var rowFrames: [Int64: CGRect] = [:]
    @State private var suppressRowActivation = false
    @State private var showsBulkPastePanel = false
    @State private var isCursorPanelPinned = false
    @State private var isCursorPanelResizeModeEnabled = false
    @State private var hoveredClipID: Int64?
    @ObservedObject private var selectionResetController: HistorySelectionResetController
    private let blobStorage: BlobStorage
    private let thumbnailCache: ImageThumbnailCache
    private let usesTransparentBackground: Bool
    private let onCursorPanelPinChanged: (Bool) -> Void
    private let onCursorPanelResizeModeChanged: (Bool) -> Void
    private let onCursorPanelFilterMenuPresentationChanged: (Bool) -> Void
    private let onCursorPanelClearConfirmationChanged: (Bool) -> Void
    private static let listCoordinateSpace = "KPasteHistoryList"

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        restorer: ClipRestorer,
        bulkPasteController: BulkPasteController,
        onRestored: @escaping () -> Void,
        usesTransparentBackground: Bool = false,
        onCursorPanelPinChanged: @escaping (Bool) -> Void = { _ in },
        onCursorPanelResizeModeChanged: @escaping (Bool) -> Void = { _ in },
        onCursorPanelFilterMenuPresentationChanged: @escaping (Bool) -> Void = { _ in },
        onCursorPanelClearConfirmationChanged: @escaping (Bool) -> Void = { _ in },
        selectionResetController: HistorySelectionResetController
    ) {
        self.blobStorage = blobStorage
        thumbnailCache = ImageThumbnailCache(blobStorage: blobStorage)
        self.usesTransparentBackground = usesTransparentBackground
        self.onCursorPanelPinChanged = onCursorPanelPinChanged
        self.onCursorPanelResizeModeChanged = onCursorPanelResizeModeChanged
        self.onCursorPanelFilterMenuPresentationChanged = onCursorPanelFilterMenuPresentationChanged
        self.onCursorPanelClearConfirmationChanged = onCursorPanelClearConfirmationChanged
        self.selectionResetController = selectionResetController
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
                        filter: $viewModel.filter,
                        pinChanged: onCursorPanelPinChanged,
                        resizeModeChanged: onCursorPanelResizeModeChanged,
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
        } else if viewModel.pinned.isEmpty && viewModel.history.isEmpty {
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
            List {
                if !viewModel.pinned.isEmpty {
                    Section("Pinned") {
                        rows(viewModel.pinned)
                    }
                }

                if !viewModel.history.isEmpty {
                    Section {
                        rows(viewModel.history)
                    }
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
                    guard let topClipID = (viewModel.pinned.first ?? viewModel.history.first)?.id else {
                        return
                    }
                    scrollProxy.scrollTo(topClipID, anchor: .top)
                }
            }
        }
    }

    private var orderedClips: [ClipRecord] {
        viewModel.pinned + viewModel.history
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
            .contextMenu {
                if viewModel.canBulkSelect(clip) {
                    Button(
                        viewModel.selectionIndex(for: clip) == nil
                            ? "Add to bulk paste"
                            : "Remove from bulk paste"
                    ) {
                        viewModel.toggleSelection(clip)
                    }
                }
                Button(clip.pinned ? "Unpin" : "Pin") {
                    viewModel.togglePinned(clip)
                }
                Button("Delete", role: .destructive) {
                    viewModel.delete(clip)
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
                    isSelected: clip.id.map(viewModel.selectedClipIDs.contains) == true,
                    onActivate: { viewModel.restore(clip) },
                    onSelectionChanged: handleTextSelection,
                    onSelectionFinished: finishTextSelection,
                    onToggleSelection: { viewModel.toggleSelection(clip) },
                    onTogglePinned: { viewModel.togglePinned(clip) },
                    onDelete: { viewModel.delete(clip) }
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
                        isPinned: clip.pinned,
                        onActivate: { viewModel.restore(clip) },
                        onTogglePinned: { viewModel.togglePinned(clip) },
                        onDelete: { viewModel.delete(clip) }
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
        viewModel.clearSelection()
    }
}
