import AppKit
import SwiftUI

struct TextSelectionSourceView: NSViewRepresentable {
    let clip: ClipRecord
    let isSelected: Bool
    let onActivate: () -> Void
    let onSelectionChanged: ([ClipRecord]) -> Void
    let onSelectionFinished: () -> Void
    let onToggleSelection: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> TextSelectionSourceNSView {
        TextSelectionSourceNSView(
            clip: clip,
            isSelected: isSelected,
            onActivate: onActivate,
            onSelectionChanged: onSelectionChanged,
            onSelectionFinished: onSelectionFinished,
            onToggleSelection: onToggleSelection,
            onTogglePinned: onTogglePinned,
            onDelete: onDelete
        )
    }

    func updateNSView(_ nsView: TextSelectionSourceNSView, context: Context) {
        nsView.clip = clip
        nsView.isSelected = isSelected
        nsView.onActivate = onActivate
        nsView.onSelectionChanged = onSelectionChanged
        nsView.onSelectionFinished = onSelectionFinished
        nsView.onToggleSelection = onToggleSelection
        nsView.onTogglePinned = onTogglePinned
        nsView.onDelete = onDelete
    }
}

final class TextSelectionSourceNSView: NSView {
    var clip: ClipRecord
    var isSelected: Bool
    var onActivate: () -> Void
    var onSelectionChanged: ([ClipRecord]) -> Void
    var onSelectionFinished: () -> Void
    var onToggleSelection: () -> Void
    var onTogglePinned: () -> Void
    var onDelete: () -> Void

    private var mouseDownLocationInWindow: NSPoint?
    private var startedSelecting = false

    init(
        clip: ClipRecord,
        isSelected: Bool,
        onActivate: @escaping () -> Void,
        onSelectionChanged: @escaping ([ClipRecord]) -> Void,
        onSelectionFinished: @escaping () -> Void,
        onToggleSelection: @escaping () -> Void,
        onTogglePinned: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.clip = clip
        self.isSelected = isSelected
        self.onActivate = onActivate
        self.onSelectionChanged = onSelectionChanged
        self.onSelectionFinished = onSelectionFinished
        self.onToggleSelection = onToggleSelection
        self.onTogglePinned = onTogglePinned
        self.onDelete = onDelete
        super.init(frame: .zero)
        toolTip = "Drag across text clips to select"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocationInWindow = event.locationInWindow
        startedSelecting = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocationInWindow else {
            return
        }

        let current = event.locationInWindow
        guard startedSelecting || hypot(current.x - start.x, current.y - start.y) >= 3 else {
            return
        }

        startedSelecting = true
        onSelectionChanged(textClips(between: start.y, and: current.y))
    }

    override func mouseUp(with event: NSEvent) {
        let shouldActivate = !startedSelecting
        mouseDownLocationInWindow = nil
        startedSelecting = false

        if shouldActivate {
            onActivate()
        } else {
            onSelectionFinished()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let selectionItem = NSMenuItem(
            title: isSelected ? "Remove from bulk paste" : "Add to bulk paste",
            action: #selector(toggleSelection),
            keyEquivalent: ""
        )
        selectionItem.target = self
        menu.addItem(selectionItem)

        let pinItem = NSMenuItem(
            title: clip.pinned ? "Unpin" : "Pin",
            action: #selector(togglePinned),
            keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        let deleteItem = NSMenuItem(
            title: "Delete",
            action: #selector(deleteClip),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func toggleSelection() {
        onToggleSelection()
    }

    @objc private func togglePinned() {
        onTogglePinned()
    }

    @objc private func deleteClip() {
        onDelete()
    }

    private func textClips(between startY: CGFloat, and currentY: CGFloat) -> [ClipRecord] {
        guard let contentView = window?.contentView else {
            return [clip]
        }

        let lowerBound = min(startY, currentY)
        let upperBound = max(startY, currentY)
        var rows = textSelectionRows(in: contentView).filter { row in
            guard row.window === window, !row.isHidden else {
                return false
            }
            let frame = row.convert(row.bounds, to: nil)
            return frame.maxY >= lowerBound && frame.minY <= upperBound
        }

        if currentY < startY {
            rows.sort { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).midY > rhs.convert(rhs.bounds, to: nil).midY
            }
        } else {
            rows.sort { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).midY < rhs.convert(rhs.bounds, to: nil).midY
            }
        }
        return rows.map(\.clip)
    }

    private func textSelectionRows(in view: NSView) -> [TextSelectionSourceNSView] {
        var rows = view.subviews.flatMap(textSelectionRows)
        if let row = view as? TextSelectionSourceNSView {
            rows.append(row)
        }
        return rows
    }
}

struct FileDragSourceView: NSViewRepresentable {
    let urls: [URL]
    let isPinned: Bool
    let onActivate: () -> Void
    let onTogglePinned: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> FileDragSourceNSView {
        FileDragSourceNSView(
            urls: urls,
            isPinned: isPinned,
            onActivate: onActivate,
            onTogglePinned: onTogglePinned,
            onDelete: onDelete
        )
    }

    func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.isPinned = isPinned
        nsView.onActivate = onActivate
        nsView.onTogglePinned = onTogglePinned
        nsView.onDelete = onDelete
    }
}

final class FileDragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL]
    var isPinned: Bool
    var onActivate: () -> Void
    var onTogglePinned: () -> Void
    var onDelete: () -> Void
    private var mouseDownLocation: NSPoint?
    private var startedDragging = false

    init(
        urls: [URL],
        isPinned: Bool,
        onActivate: @escaping () -> Void,
        onTogglePinned: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.urls = urls
        self.isPinned = isPinned
        self.onActivate = onActivate
        self.onTogglePinned = onTogglePinned
        self.onDelete = onDelete
        super.init(frame: .zero)
        toolTip = "Drag to another app"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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
        let shouldActivate = !startedDragging
        mouseDownLocation = nil
        startedDragging = false
        if shouldActivate {
            onActivate()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let pinItem = NSMenuItem(
            title: isPinned ? "Unpin" : "Pin",
            action: #selector(togglePinned),
            keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        let deleteItem = NSMenuItem(
            title: "Delete",
            action: #selector(deleteClip),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func togglePinned() {
        onTogglePinned()
    }

    @objc private func deleteClip() {
        onDelete()
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
