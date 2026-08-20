import AppKit
import SwiftUI

@MainActor
final class PasteFallbackPanelController {
    enum Presentation: Equatable {
        case permissionRequired
        case manualPaste
    }

    static var permissionTitle: String {
        "\(AppConfiguration.name) needs permission to paste into other apps."
    }
    static var permissionMessage: String {
        "Enable \(AppConfiguration.name) in Privacy & Security → Accessibility."
    }
    static let manualTitle = "Copied — press ⌘V to paste"
    static let manualMessage = "Automatic paste could not reach the previous app."

    private static let permissionPanelSize = NSSize(width: 520, height: 170)
    private static let manualPanelSize = NSSize(width: 500, height: 96)

    private let panel: NSPanel
    private let pasteAutomationController: PasteAutomationController
    private var dismissalTask: Task<Void, Never>?
    private var presentation: Presentation?

    init(pasteAutomationController: PasteAutomationController) {
        self.pasteAutomationController = pasteAutomationController
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.permissionPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
    }

    func showPermissionRequired() {
        show(.permissionRequired)
    }

    func showManualPaste() {
        show(.manualPaste)
    }

    private func show(_ presentation: Presentation) {
        dismissalTask?.cancel()
        if self.presentation == .permissionRequired, presentation != .permissionRequired {
            pasteAutomationController.setAuthorizationSurface(
                .permissionPrompt,
                visible: false
            )
        }
        self.presentation = presentation
        let panelSize = presentation == .permissionRequired
            ? Self.permissionPanelSize
            : Self.manualPanelSize
        panel.setContentSize(panelSize)
        panel.contentViewController = NSHostingController(
            rootView: PasteFallbackView(
                presentation: presentation,
                pasteAutomationController: pasteAutomationController,
                dismiss: { [weak self] in self?.hide() }
            )
        )
        if presentation == .permissionRequired {
            pasteAutomationController.setAuthorizationSurface(
                .permissionPrompt,
                visible: true
            )
        }
        let pointer = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(pointer) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let origin = NSPoint(
            x: min(
                max(pointer.x - panelSize.width / 2, visibleFrame.minX + 8),
                visibleFrame.maxX - panelSize.width - 8
            ),
            y: min(
                max(pointer.y + 20, visibleFrame.minY + 8),
                visibleFrame.maxY - panelSize.height - 8
            )
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        if presentation == .manualPaste {
            dismissalTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else {
                    return
                }
                self?.hide()
            }
        }
    }

    private func hide() {
        dismissalTask?.cancel()
        if presentation == .permissionRequired {
            pasteAutomationController.setAuthorizationSurface(
                .permissionPrompt,
                visible: false
            )
        }
        presentation = nil
        panel.orderOut(nil)
    }
}

private struct PasteFallbackView: View {
    let presentation: PasteFallbackPanelController.Presentation
    @ObservedObject var pasteAutomationController: PasteAutomationController
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if presentation == .permissionRequired {
                    HStack(spacing: 12) {
                        Button(
                            pasteAutomationController.isPostEventAuthorized
                                ? "Done"
                                : "Open System Settings"
                        ) {
                            if pasteAutomationController.isPostEventAuthorized {
                                dismiss()
                            } else {
                                Task {
                                    await pasteAutomationController.requestAuthorization()
                                }
                            }
                        }
                        .controlSize(.small)

                        if pasteAutomationController.permissionRequestState == .requesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(
            width: presentation == .permissionRequired ? 520 : 500,
            height: presentation == .permissionRequired ? 170 : 96
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private var iconName: String {
        if presentation == .manualPaste {
            return "doc.on.clipboard.fill"
        }
        return pasteAutomationController.isPostEventAuthorized
            ? "checkmark.circle.fill"
            : "accessibility"
    }

    private var iconColor: Color {
        pasteAutomationController.isPostEventAuthorized ? .green : .primary
    }

    private var title: String {
        switch presentation {
        case .permissionRequired:
            return pasteAutomationController.isPostEventAuthorized
                ? "Automatic paste permission granted"
                : PasteFallbackPanelController.permissionTitle
        case .manualPaste:
            return PasteFallbackPanelController.manualTitle
        }
    }

    private var message: String {
        switch presentation {
        case .permissionRequired:
            return pasteAutomationController.isPostEventAuthorized
                ? "The next selected clip will paste automatically."
                : PasteFallbackPanelController.permissionMessage
        case .manualPaste:
            return PasteFallbackPanelController.manualMessage
        }
    }
}
