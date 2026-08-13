import AppKit
import SwiftUI

enum MouseSwipeDeleteIntent: Equatable {
    case undecided
    case deleteSwipe
    case otherDrag
}

enum MouseSwipeDeleteGesture {
    static let axisLockDistance: CGFloat = 6
    static let deletionDistance: CGFloat = 48
    static let maximumRevealDistance: CGFloat = 92

    static func intent(for translation: NSSize) -> MouseSwipeDeleteIntent {
        guard hypot(translation.width, translation.height) >= axisLockDistance else {
            return .undecided
        }
        if translation.width < 0,
           abs(translation.width) > abs(translation.height) * 1.25 {
            return .deleteSwipe
        }
        return .otherDrag
    }

    static func shouldDelete(translation: NSSize) -> Bool {
        intent(for: translation) == .deleteSwipe
            && translation.width <= -deletionDistance
    }

    static func visualOffset(for translation: CGFloat) -> CGFloat {
        min(max(translation, -maximumRevealDistance), 0)
    }
}

private final class TrackpadSwipeDeleteHandler {
    private var accumulatedTranslation: CGFloat = 0

    func handle(
        _ event: NSEvent,
        onSwipeChanged: (CGFloat) -> Void,
        onDelete: () -> Void
    ) -> Bool {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else {
            return false
        }

        let horizontalDelta = physicalHorizontalDelta(for: event)
        guard abs(horizontalDelta) > abs(event.scrollingDeltaY) else {
            return false
        }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            accumulatedTranslation = 0
        }
        accumulatedTranslation += horizontalDelta
        onSwipeChanged(accumulatedTranslation)

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let shouldDelete = MouseSwipeDeleteGesture.shouldDelete(
                translation: NSSize(width: accumulatedTranslation, height: 0)
            )
            accumulatedTranslation = 0
            if shouldDelete {
                onDelete()
            } else {
                onSwipeChanged(0)
            }
        }
        return true
    }

    private func physicalHorizontalDelta(for event: NSEvent) -> CGFloat {
        event.scrollingDeltaX * (event.isDirectionInvertedFromDevice ? -1 : 1)
    }
}

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
    let onDelete: () -> Void
    let onSwipeChanged: (CGFloat) -> Void
    let onSelectionChanged: ([ClipRecord]) -> Void
    let onSelectionFinished: () -> Void

    func makeNSView(context: Context) -> TextSelectionSourceNSView {
        TextSelectionSourceNSView(
            clip: clip,
            onActivate: onActivate,
            onDelete: onDelete,
            onSwipeChanged: onSwipeChanged,
            onSelectionChanged: onSelectionChanged,
            onSelectionFinished: onSelectionFinished
        )
    }

    func updateNSView(_ nsView: TextSelectionSourceNSView, context: Context) {
        nsView.clip = clip
        nsView.onActivate = onActivate
        nsView.onDelete = onDelete
        nsView.onSwipeChanged = onSwipeChanged
        nsView.onSelectionChanged = onSelectionChanged
        nsView.onSelectionFinished = onSelectionFinished
    }
}

final class TextSelectionSourceNSView: NSView {
    var clip: ClipRecord
    var onActivate: () -> Void
    var onDelete: () -> Void
    var onSwipeChanged: (CGFloat) -> Void
    var onSelectionChanged: ([ClipRecord]) -> Void
    var onSelectionFinished: () -> Void

    private var mouseDownLocationInWindow: NSPoint?
    private var latestMouseLocationInWindow: NSPoint?
    private var startedSelecting = false
    private var dragIntent = MouseSwipeDeleteIntent.undecided
    private let trackpadSwipeHandler = TrackpadSwipeDeleteHandler()

    init(
        clip: ClipRecord,
        onActivate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSwipeChanged: @escaping (CGFloat) -> Void,
        onSelectionChanged: @escaping ([ClipRecord]) -> Void,
        onSelectionFinished: @escaping () -> Void
    ) {
        self.clip = clip
        self.onActivate = onActivate
        self.onDelete = onDelete
        self.onSwipeChanged = onSwipeChanged
        self.onSelectionChanged = onSelectionChanged
        self.onSelectionFinished = onSelectionFinished
        super.init(frame: .zero)
        toolTip = "Click to paste\nDrag vertically to select\nDrag left to delete"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if !trackpadSwipeHandler.handle(
            event,
            onSwipeChanged: onSwipeChanged,
            onDelete: onDelete
        ) {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocationInWindow = event.locationInWindow
        latestMouseLocationInWindow = event.locationInWindow
        startedSelecting = false
        dragIntent = .undecided
        onSwipeChanged(0)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocationInWindow else {
            return
        }

        let current = event.locationInWindow
        latestMouseLocationInWindow = current
        if dragIntent == .undecided {
            dragIntent = MouseSwipeDeleteGesture.intent(
                for: translation(from: start, to: current)
            )
        }
        guard dragIntent == .otherDrag else {
            if dragIntent == .deleteSwipe {
                onSwipeChanged(current.x - start.x)
            }
            return
        }

        startedSelecting = true
        onSelectionChanged(textClips(between: start.y, and: current.y))
    }

    override func mouseUp(with event: NSEvent) {
        let start = mouseDownLocationInWindow
        let end = latestMouseLocationInWindow ?? event.locationInWindow
        let shouldDelete = start.map {
            MouseSwipeDeleteGesture.shouldDelete(
                translation: translation(from: $0, to: end)
            )
        } ?? false
        let shouldActivate = dragIntent == .undecided && !startedSelecting
        let didSelect = startedSelecting
        mouseDownLocationInWindow = nil
        latestMouseLocationInWindow = nil
        startedSelecting = false
        dragIntent = .undecided

        if shouldDelete {
            onDelete()
        } else if shouldActivate {
            onActivate()
        } else {
            onSwipeChanged(0)
            if didSelect {
                onSelectionFinished()
            }
        }
    }

    private func translation(from start: NSPoint, to end: NSPoint) -> NSSize {
        NSSize(width: end.x - start.x, height: end.y - start.y)
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
    let onDelete: () -> Void
    let onSwipeChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> FileDragSourceNSView {
        FileDragSourceNSView(
            urls: urls,
            onActivate: onActivate,
            onDelete: onDelete,
            onSwipeChanged: onSwipeChanged
        )
    }

    func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.onActivate = onActivate
        nsView.onDelete = onDelete
        nsView.onSwipeChanged = onSwipeChanged
    }
}

final class FileDragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL]
    var onActivate: () -> Void
    var onDelete: () -> Void
    var onSwipeChanged: (CGFloat) -> Void
    private var mouseDownLocation: NSPoint?
    private var latestMouseLocation: NSPoint?
    private var startedDragging = false
    private var dragIntent = MouseSwipeDeleteIntent.undecided
    private let trackpadSwipeHandler = TrackpadSwipeDeleteHandler()

    init(
        urls: [URL],
        onActivate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSwipeChanged: @escaping (CGFloat) -> Void
    ) {
        self.urls = urls
        self.onActivate = onActivate
        self.onDelete = onDelete
        self.onSwipeChanged = onSwipeChanged
        super.init(frame: .zero)
        toolTip = "Drag to another app\nDrag left to delete"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if !trackpadSwipeHandler.handle(
            event,
            onSwipeChanged: onSwipeChanged,
            onDelete: onDelete
        ) {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        latestMouseLocation = mouseDownLocation
        startedDragging = false
        dragIntent = .undecided
        onSwipeChanged(0)
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
        latestMouseLocation = currentLocation
        if dragIntent == .undecided {
            dragIntent = MouseSwipeDeleteGesture.intent(
                for: translation(from: mouseDownLocation, to: currentLocation)
            )
        }
        guard dragIntent == .otherDrag else {
            if dragIntent == .deleteSwipe {
                onSwipeChanged(currentLocation.x - mouseDownLocation.x)
            }
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
        let currentLocation = latestMouseLocation
            ?? convert(event.locationInWindow, from: nil)
        let shouldDelete = mouseDownLocation.map {
            MouseSwipeDeleteGesture.shouldDelete(
                translation: translation(from: $0, to: currentLocation)
            )
        } ?? false
        let shouldActivate = dragIntent == .undecided && !startedDragging
        mouseDownLocation = nil
        latestMouseLocation = nil
        startedDragging = false
        dragIntent = .undecided
        if shouldDelete {
            onDelete()
        } else if shouldActivate {
            onActivate()
        } else {
            onSwipeChanged(0)
        }
    }

    private func translation(from start: NSPoint, to end: NSPoint) -> NSSize {
        NSSize(width: end.x - start.x, height: end.y - start.y)
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

struct MouseSwipeActionView: NSViewRepresentable {
    let onActivate: () -> Void
    let onDelete: () -> Void
    let onSwipeChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> MouseSwipeActionNSView {
        MouseSwipeActionNSView(
            onActivate: onActivate,
            onDelete: onDelete,
            onSwipeChanged: onSwipeChanged
        )
    }

    func updateNSView(_ nsView: MouseSwipeActionNSView, context: Context) {
        nsView.onActivate = onActivate
        nsView.onDelete = onDelete
        nsView.onSwipeChanged = onSwipeChanged
    }
}

final class MouseSwipeActionNSView: NSView {
    var onActivate: () -> Void
    var onDelete: () -> Void
    var onSwipeChanged: (CGFloat) -> Void
    private var mouseDownLocation: NSPoint?
    private var latestMouseLocation: NSPoint?
    private var dragIntent = MouseSwipeDeleteIntent.undecided
    private let trackpadSwipeHandler = TrackpadSwipeDeleteHandler()

    init(
        onActivate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSwipeChanged: @escaping (CGFloat) -> Void
    ) {
        self.onActivate = onActivate
        self.onDelete = onDelete
        self.onSwipeChanged = onSwipeChanged
        super.init(frame: .zero)
        toolTip = "Click to paste\nDrag left to delete"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if !trackpadSwipeHandler.handle(
            event,
            onSwipeChanged: onSwipeChanged,
            onDelete: onDelete
        ) {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        latestMouseLocation = mouseDownLocation
        dragIntent = .undecided
        onSwipeChanged(0)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else {
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        latestMouseLocation = current
        if dragIntent == .undecided {
            dragIntent = MouseSwipeDeleteGesture.intent(
                for: NSSize(width: current.x - start.x, height: current.y - start.y)
            )
        }
        if dragIntent == .deleteSwipe {
            onSwipeChanged(current.x - start.x)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let end = latestMouseLocation ?? convert(event.locationInWindow, from: nil)
        let shouldDelete = mouseDownLocation.map {
            MouseSwipeDeleteGesture.shouldDelete(
                translation: NSSize(width: end.x - $0.x, height: end.y - $0.y)
            )
        } ?? false
        let shouldActivate = dragIntent == .undecided
        mouseDownLocation = nil
        latestMouseLocation = nil
        dragIntent = .undecided

        if shouldDelete {
            onDelete()
        } else if shouldActivate {
            onActivate()
        } else {
            onSwipeChanged(0)
        }
    }
}
