import AppKit
import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel
    @State private var rowFrames: [Int64: CGRect] = [:]
    @State private var dragStartY: CGFloat?
    @State private var suppressRowActivation = false
    @State private var showsBulkPastePanel = false
    @State private var isCursorPanelPinned = false
    @ObservedObject private var selectionResetController: HistorySelectionResetController
    private let blobStorage: BlobStorage
    private let thumbnailCache: ImageThumbnailCache
    private let usesTransparentBackground: Bool
    private let onCursorPanelPinChanged: (Bool) -> Void
    private static let listCoordinateSpace = "KPasteHistoryList"

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        restorer: ClipRestorer,
        bulkPasteController: BulkPasteController,
        onRestored: @escaping () -> Void,
        usesTransparentBackground: Bool = false,
        onCursorPanelPinChanged: @escaping (Bool) -> Void = { _ in },
        selectionResetController: HistorySelectionResetController
    ) {
        self.blobStorage = blobStorage
        thumbnailCache = ImageThumbnailCache(blobStorage: blobStorage)
        self.usesTransparentBackground = usesTransparentBackground
        self.onCursorPanelPinChanged = onCursorPanelPinChanged
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
                    CursorPanelControls(
                        isPinned: $isCursorPanelPinned,
                        pinChanged: onCursorPanelPinChanged
                    )
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
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .trailing
            )
        }
    }

    private var panelSurface: some View {
        ZStack(alignment: .trailing) {
            mainWindow

            if usesTransparentBackground,
                showsBulkPastePanel,
                viewModel.selectedCount > 1
            {
                BulkPasteIconRail { format in
                    viewModel.pasteSelection(format: format)
                }
                .padding(.trailing, 4)
            }
        }
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
        .onChange(of: viewModel.selectedCount) { selectedCount in
            if selectedCount < 2 {
                showsBulkPastePanel = false
            } else if !suppressRowActivation {
                showsBulkPastePanel = true
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
                        viewModel.pasteSelectionAsIs()
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
            ZStack(alignment: .leading) {
                Button {
                    guard !suppressRowActivation else {
                        return
                    }
                    viewModel.restore(clip)
                } label: {
                    ClipRowView(
                        clip: clip,
                        selectionIndex: viewModel.selectionIndex(for: clip),
                        thumbnailCache: thumbnailCache
                    )
                }
                .buttonStyle(.plain)

                if
                    let urls = try? blobStorage.dragURLs(for: clip),
                    !urls.isEmpty
                {
                    FileDragSourceView(urls: urls)
                        .frame(
                            width: clip.type == ClipContentType.image.rawValue ? 18 : 42,
                            height: clip.type == ClipContentType.image.rawValue ? 18 : 42
                        )
                        .padding(clip.type == ClipContentType.image.rawValue ? 2 : 0)
                        .background {
                            if clip.type == ClipContentType.image.rawValue {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                        .offset(
                            x: clip.type == ClipContentType.image.rawValue ? 20 : 0,
                            y: clip.type == ClipContentType.image.rawValue ? 10 : 0
                        )
                }
            }
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
                viewModel.selectionIndex(for: clip) == nil
                    ? Color.clear
                    : Color.accentColor.opacity(0.18)
            )
            .simultaneousGesture(
                selectionDragGesture,
                including: viewModel.canBulkSelect(clip) ? .all : .none
            )
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

    private var selectionDragGesture: some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(Self.listCoordinateSpace)
        )
        .onChanged(handleSelectionDrag)
        .onEnded { _ in finishSelectionDrag() }
    }

    private func handleSelectionDrag(_ value: DragGesture.Value) {
        if dragStartY == nil {
            dragStartY = value.startLocation.y
            suppressRowActivation = true
            showsBulkPastePanel = false
        }

        guard let dragStartY else {
            return
        }
        let lowerBound = min(dragStartY, value.location.y)
        let upperBound = max(dragStartY, value.location.y)
        var selectedClips = (viewModel.pinned + viewModel.history).filter { clip in
            guard
                viewModel.canBulkSelect(clip),
                let id = clip.id,
                let frame = rowFrames[id]
            else {
                return false
            }
            return frame.maxY >= lowerBound && frame.minY <= upperBound
        }
        if value.location.y < dragStartY {
            selectedClips.reverse()
        }
        viewModel.replaceSelection(with: selectedClips)
    }

    private func finishSelectionDrag() {
        dragStartY = nil
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
        dragStartY = nil
        suppressRowActivation = false
        showsBulkPastePanel = false
        viewModel.clearSelection()
    }
}

private struct ClipRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]

    static func reduce(
        value: inout [Int64: CGRect],
        nextValue: () -> [Int64: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct CursorPanelControls: View {
    @Binding var isPinned: Bool
    let pinChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                WindowDragHandle()
            }
            .frame(width: 24, height: 24)
            .help("Move KPaste")

            Button {
                isPinned.toggle()
                pinChanged(isPinned)
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    if isPinned {
                        Circle()
                            .fill(Color.accentColor)
                    }
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isPinned ? Color.white : Color.secondary)
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin KPaste" : "Keep KPaste above other windows")
        }
        .frame(height: 24)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleNSView {
        WindowDragHandleNSView()
    }

    func updateNSView(_ nsView: WindowDragHandleNSView, context: Context) {}
}

private final class WindowDragHandleNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

private struct BulkPasteIconRail: View {
    let paste: (BulkPasteFormat) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(BulkPasteFormat.allCases) { format in
                Button {
                    paste(format)
                } label: {
                    formatIcon(format)
                        .frame(width: 32, height: 32)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(format.title)
            }
        }
    }

    @ViewBuilder
    private func formatIcon(_ format: BulkPasteFormat) -> some View {
        switch format {
        case .newline:
            Image(systemName: "return.left")
        case .bullets:
            Image(systemName: "list.bullet")
        case .commaSpace:
            Text(",")
                .font(.headline.bold())
        case .periodSpace:
            Text(".")
                .font(.headline.bold())
        case .slash:
            Text("/")
                .font(.headline.bold())
        }
    }
}

private struct HistoryTickScrollIndicator: View {
    let itemCount: Int
    let activeItemIndex: Int
    let scrollToItem: (Int) -> Void

    private var tickCount: Int {
        min(max(itemCount, 1), 30)
    }

    private var activeTickIndex: Int {
        guard itemCount > 1, tickCount > 1 else {
            return 0
        }
        return Int(
            round(
                Double(activeItemIndex)
                    / Double(itemCount - 1)
                    * Double(tickCount - 1)
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 5) {
                ForEach(0..<tickCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.primary.opacity(opacity(for: index)))
                        .frame(width: 8, height: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scroll(using: value.location.y, height: proxy.size.height)
                    }
            )
        }
        .frame(width: 8)
        .help("Scroll history")
    }

    private func opacity(for index: Int) -> Double {
        switch abs(index - activeTickIndex) {
        case 0: 1
        case 1: 0.8
        case 2: 0.6
        default: 0.24
        }
    }

    private func scroll(using verticalLocation: CGFloat, height: CGFloat) {
        guard itemCount > 0, height > 0 else {
            return
        }
        let tickStep: CGFloat = 7
        let trackHeight = CGFloat(tickCount - 1) * tickStep + 2
        let firstTickCenter = (height - trackHeight) / 2 + 1
        let lastTickCenter = firstTickCenter + CGFloat(tickCount - 1) * tickStep
        let trackRange = max(lastTickCenter - firstTickCenter, 1)
        let progress = min(
            max((verticalLocation - firstTickCenter) / trackRange, 0),
            1
        )
        let itemIndex = Int(round(progress * CGFloat(itemCount - 1)))
        scrollToItem(itemIndex)
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
    let selectionIndex: Int?
    let thumbnailCache: ImageThumbnailCache

    var body: some View {
        HStack(spacing: 10) {
            formatView
                .frame(width: 42, height: 42)

            HStack(spacing: 6) {
                Text(clip.previewText.isEmpty ? "Untitled clip" : clip.previewText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let selectionIndex {
                    Text("\(selectionIndex)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
            }

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
                    .frame(
                        width: ClipTimestampFormatter.dayColumnWidth,
                        alignment: .trailing
                    )
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var formatView: some View {
        switch ClipContentType(rawValue: clip.type) {
        case .text:
            formatLabel("TXT")
        case .rtf:
            formatLabel("RTF")
        case .url:
            formatLabel("URL")
        case .image:
            if let id = clip.id {
                ImageThumbnailView(clipID: id, cache: thumbnailCache)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        case .file:
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        case nil:
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func formatLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
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

enum ClipTimestampFormatter {
    struct Components: Equatable {
        let day: String
        let time: String
    }

    static let dayColumnWidth: CGFloat = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let labels = (formatter.weekdaySymbols ?? []) + ["Today", "Yesterday"]
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let width = labels.map { label in
            (label as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return ceil(width)
    }()

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

private struct FileDragSourceView: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> FileDragSourceNSView {
        FileDragSourceNSView(urls: urls)
    }

    func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.urls = urls
    }
}

private final class FileDragSourceNSView: NSImageView, NSDraggingSource {
    var urls: [URL]
    private var mouseDownLocation: NSPoint?
    private var startedDragging = false

    init(urls: [URL]) {
        self.urls = urls
        super.init(frame: .zero)
        image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "Drag files"
        )
        imageScaling = .scaleProportionallyDown
        contentTintColor = .secondaryLabelColor
        toolTip = "Drag to copy"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        startedDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            !startedDragging,
            !urls.isEmpty,
            let mouseDownLocation
        else {
            return
        }

        let currentLocation = convert(event.locationInWindow, from: nil)
        guard hypot(
            currentLocation.x - mouseDownLocation.x,
            currentLocation.y - mouseDownLocation.y
        ) >= 3 else {
            return
        }

        startedDragging = true
        let draggingItems = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 4)) * 3
            item.setDraggingFrame(
                NSRect(
                    x: bounds.midX - 16 + offset,
                    y: bounds.midY - 16 - offset,
                    width: 32,
                    height: 32
                ),
                contents: icon
            )
            return item
        }
        _ = beginDraggingSession(
            with: draggingItems,
            event: event,
            source: self
        )
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        startedDragging = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
