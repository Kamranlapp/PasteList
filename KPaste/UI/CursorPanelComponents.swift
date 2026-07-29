import AppKit
import SwiftUI

struct CursorPanelControls: View {
    @Binding var isPinned: Bool
    @Binding var isResizeModeEnabled: Bool
    @Binding var pastesAsPlainText: Bool
    @Binding var filter: ClipHistoryFilter
    let pinChanged: (Bool) -> Void
    let resizeModeChanged: (Bool) -> Void
    let clearHistory: () -> Void
    let filterMenuPresentationChanged: (Bool) -> Void
    let clearConfirmationChanged: (Bool) -> Void
    @State private var isHovering = false
    @State private var hoveredControl: Control?
    @State private var isFilterMenuPresented = false
    @State private var showsClearConfirmation = false

    private enum Control: String {
        case pin = "Pin"
        case move = "Move"
        case resize = "Resize"
        case plainText = "Plain text"
        case filter = "Filter"
        case clear = "Clear"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HoverTrackingView { isInside in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = isInside
                }
            }

            HStack(spacing: 8) {
                Button {
                    isPinned.toggle()
                    pinChanged(isPinned)
                } label: {
                    controlCircle(
                        systemName: isPinned ? "pin.fill" : "pin",
                        isActive: isPinned
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { tooltip(for: .pin) }
                .onHover { setHoveredControl(.pin, isInside: $0) }

                ZStack {
                    controlCircle(
                        systemName: "arrow.up.and.down.and.arrow.left.and.right",
                        isActive: false
                    )
                    WindowDragHandle()
                }
                .frame(width: 24, height: 24)
                .overlay(alignment: .top) { tooltip(for: .move) }
                .onHover { setHoveredControl(.move, isInside: $0) }

                Button {
                    isResizeModeEnabled.toggle()
                    resizeModeChanged(isResizeModeEnabled)
                } label: {
                    controlCircle(
                        systemName: "arrow.up.left.and.arrow.down.right",
                        isActive: isResizeModeEnabled
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { tooltip(for: .resize) }
                .onHover { setHoveredControl(.resize, isInside: $0) }

                Button {
                    pastesAsPlainText.toggle()
                } label: {
                    controlCircle(
                        systemName: "textformat",
                        isActive: pastesAsPlainText
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { tooltip(for: .plainText) }
                .onHover { setHoveredControl(.plainText, isInside: $0) }

                ZStack {
                    controlCircle(
                        systemName: "line.3.horizontal.decrease",
                        isActive: filter != .all
                    )

                    NativeFilterMenuControl(
                        selection: $filter,
                        presentationChanged: { isPresented in
                            isFilterMenuPresented = isPresented
                            filterMenuPresentationChanged(isPresented)
                        }
                    )
                }
                .frame(width: 24, height: 24)
                .overlay(alignment: .top) { tooltip(for: .filter) }
                .onHover { setHoveredControl(.filter, isInside: $0) }

                Button {
                    clearConfirmationChanged(true)
                    showsClearConfirmation = true
                } label: {
                    controlCircle(
                        systemName: "trash",
                        isActive: false,
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { tooltip(for: .clear) }
                .onHover { setHoveredControl(.clear, isInside: $0) }
            }
            .padding(.leading, 16)
            .padding(.top, StatusItemController.cursorWindowTooltipHeight)
            .opacity(isHovering || isFilterMenuPresented || showsClearConfirmation ? 1 : 0)
            .allowsHitTesting(isHovering || isFilterMenuPresented || showsClearConfirmation)
        }
        .frame(width: 218, height: 92, alignment: .topLeading)
        .alert("Clear Clipboard History?", isPresented: clearConfirmationBinding) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: clearHistory)
        } message: {
            Text(
                "All clips, including pinned clips, will be permanently deleted. "
                    + "This action cannot be undone."
            )
        }
    }

    private var clearConfirmationBinding: Binding<Bool> {
        Binding(
            get: { showsClearConfirmation },
            set: { isPresented in
                showsClearConfirmation = isPresented
                clearConfirmationChanged(isPresented)
            }
        )
    }

    private func controlCircle(
        systemName: String,
        isActive: Bool,
        tint: Color? = nil
    ) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            if isActive {
                Circle()
                    .fill(Color.accentColor)
            } else if let tint {
                Circle()
                    .fill(tint.opacity(0.14))
            }
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    isActive
                        ? Color.white
                        : tint?.opacity(0.78) ?? Color.secondary
                )
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private func tooltip(for control: Control) -> some View {
        if hoveredControl == control {
            Text(control.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .fixedSize()
                .offset(y: -StatusItemController.cursorWindowTooltipHeight)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }

    private func setHoveredControl(_ control: Control, isInside: Bool) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if isInside {
                hoveredControl = control
            } else if hoveredControl == control {
                hoveredControl = nil
            }
        }
    }
}

private struct NativeFilterMenuControl: NSViewRepresentable {
    @Binding var selection: ClipHistoryFilter
    let presentationChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TransparentPopUpButton {
        let button = TransparentPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setAccessibilityLabel("Filter clipboard history")
        context.coordinator.configure(button)
        return button
    }

    func updateNSView(_ button: TransparentPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateSelection(in: button)
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: NativeFilterMenuControl

        init(parent: NativeFilterMenuControl) {
            self.parent = parent
        }

        func configure(_ button: NSPopUpButton) {
            button.removeAllItems()
            ClipHistoryFilter.allCases.forEach { option in
                button.addItem(withTitle: option.rawValue)
            }
            button.menu?.delegate = self
            updateSelection(in: button)
        }

        func updateSelection(in button: NSPopUpButton) {
            guard
                let index = ClipHistoryFilter.allCases.firstIndex(of: parent.selection)
            else {
                return
            }
            button.selectItem(at: index)
            button.itemArray.enumerated().forEach { itemIndex, item in
                item.state = itemIndex == index ? .on : .off
            }
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard ClipHistoryFilter.allCases.indices.contains(sender.indexOfSelectedItem) else {
                return
            }
            parent.selection = ClipHistoryFilter.allCases[sender.indexOfSelectedItem]
            updateSelection(in: sender)
        }

        func menuWillOpen(_ menu: NSMenu) {
            parent.presentationChanged(true)
        }

        func menuDidClose(_ menu: NSMenu) {
            parent.presentationChanged(false)
        }
    }
}

private final class TransparentPopUpButton: NSPopUpButton {
    override func draw(_ dirtyRect: NSRect) {}
}

struct CursorPanelResizeControl: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .allowsHitTesting(false)

            CursorPanelResizeDragHandle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

private struct CursorPanelResizeDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorPanelResizeDragHandleNSView {
        CursorPanelResizeDragHandleNSView(frame: .zero)
    }

    func updateNSView(
        _ nsView: CursorPanelResizeDragHandleNSView,
        context: Context
    ) {}
}

private final class CursorPanelResizeDragHandleNSView: NSView {
    private var initialWindowFrame: NSRect?
    private var initialMouseLocation: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        initialWindowFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let initialWindowFrame,
            let initialMouseLocation
        else {
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: mouseLocation.x - initialMouseLocation.x,
            y: mouseLocation.y - initialMouseLocation.y
        )
        let resizedFrame = CursorPanelResizer.frame(
            from: initialWindowFrame,
            dragging: [.bottom, .right],
            by: delta,
            minimumSize: window.minSize,
            within: window.screen?.visibleFrame
        )
        window.setFrame(resizedFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        initialWindowFrame = nil
        initialMouseLocation = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

struct CursorPanelResizeEdges: OptionSet {
    let rawValue: UInt8

    static let top = Self(rawValue: 1 << 0)
    static let bottom = Self(rawValue: 1 << 1)
    static let left = Self(rawValue: 1 << 2)
    static let right = Self(rawValue: 1 << 3)
}

enum CursorPanelResizer {
    static func frame(
        from initialFrame: NSRect,
        dragging edges: CursorPanelResizeEdges,
        by delta: NSPoint,
        minimumSize: NSSize,
        within bounds: NSRect?
    ) -> NSRect {
        var minimumX = initialFrame.minX
        var maximumX = initialFrame.maxX
        var minimumY = initialFrame.minY
        var maximumY = initialFrame.maxY

        if edges.contains(.left) {
            minimumX = min(
                initialFrame.minX + delta.x,
                maximumX - minimumSize.width
            )
            if let bounds {
                minimumX = max(minimumX, bounds.minX)
            }
        } else if edges.contains(.right) {
            maximumX = max(
                initialFrame.maxX + delta.x,
                minimumX + minimumSize.width
            )
            if let bounds {
                maximumX = min(maximumX, bounds.maxX)
            }
        }

        if edges.contains(.bottom) {
            minimumY = min(
                initialFrame.minY + delta.y,
                maximumY - minimumSize.height
            )
            if let bounds {
                minimumY = max(minimumY, bounds.minY)
            }
        } else if edges.contains(.top) {
            maximumY = max(
                initialFrame.maxY + delta.y,
                minimumY + minimumSize.height
            )
            if let bounds {
                maximumY = min(maximumY, bounds.maxY)
            }
        }

        return NSRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    let hoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        HoverTrackingNSView(hoverChanged: hoverChanged)
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.hoverChanged = hoverChanged
    }
}

private final class HoverTrackingNSView: NSView {
    var hoverChanged: (Bool) -> Void

    init(hoverChanged: @escaping (Bool) -> Void) {
        self.hoverChanged = hoverChanged
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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

struct BulkPasteIconRail: View {
    let paste: (BulkPasteFormat) -> Void
    @State private var hoveredFormat: BulkPasteFormat?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(BulkPasteFormat.allCases) { format in
                HStack(spacing: 6) {
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
                    .onHover { isInside in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            if isInside {
                                hoveredFormat = format
                            } else if hoveredFormat == format {
                                hoveredFormat = nil
                            }
                        }
                    }

                    if hoveredFormat == format {
                        Text(format.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .frame(
                    width: StatusItemController.cursorBulkPasteRailWidth,
                    height: 32,
                    alignment: .leading
                )
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

struct HistoryTickScrollIndicator: View {
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
