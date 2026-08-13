import AppKit
import SwiftUI

/// Turns a secondary click into a single action instead of a context menu.
/// Overlaid on top of a row, it claims right-clicks and lets every other event
/// fall through to the row underneath.
struct RightClickActionView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickActionNSView {
        RightClickActionNSView(action: action)
    }

    func updateNSView(_ nsView: RightClickActionNSView, context: Context) {
        nsView.action = action
    }
}

final class RightClickActionNSView: NSView {
    var action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isSecondaryClick(NSApp.currentEvent) ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        action()
    }

    override func mouseDown(with event: NSEvent) {
        // Reached only for control-click, which macOS delivers as a left click.
        action()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }

    private func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return true
        case .leftMouseDown, .leftMouseUp:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }
}

struct TextSelectionSourceView: NSViewRepresentable {
    let clip: ClipRecord
    let onActivate: () -> Void
    let onSelectionChanged: ([ClipRecord]) -> Void
    let onSelectionFinished: () -> Void

    func makeNSView(context: Context) -> TextSelectionSourceNSView {
        TextSelectionSourceNSView(
            clip: clip,
            onActivate: onActivate,
            onSelectionChanged: onSelectionChanged,
            onSelectionFinished: onSelectionFinished
        )
    }

    func updateNSView(_ nsView: TextSelectionSourceNSView, context: Context) {
        nsView.clip = clip
        nsView.onActivate = onActivate
        nsView.onSelectionChanged = onSelectionChanged
        nsView.onSelectionFinished = onSelectionFinished
    }
}

final class TextSelectionSourceNSView: NSView {
    var clip: ClipRecord
    var onActivate: () -> Void
    var onSelectionChanged: ([ClipRecord]) -> Void
    var onSelectionFinished: () -> Void

    private var mouseDownLocationInWindow: NSPoint?
    private var startedSelecting = false

    init(
        clip: ClipRecord,
        onActivate: @escaping () -> Void,
        onSelectionChanged: @escaping ([ClipRecord]) -> Void,
        onSelectionFinished: @escaping () -> Void
    ) {
        self.clip = clip
        self.onActivate = onActivate
        self.onSelectionChanged = onSelectionChanged
        self.onSelectionFinished = onSelectionFinished
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
    let onActivate: () -> Void

    func makeNSView(context: Context) -> FileDragSourceNSView {
        FileDragSourceNSView(urls: urls, onActivate: onActivate)
    }

    func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.onActivate = onActivate
    }
}

final class FileDragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL]
    var onActivate: () -> Void
    private var mouseDownLocation: NSPoint?
    private var startedDragging = false

    init(urls: [URL], onActivate: @escaping () -> Void) {
        self.urls = urls
        self.onActivate = onActivate
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
