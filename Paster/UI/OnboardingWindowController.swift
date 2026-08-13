import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    private let state: OnboardingState
    private let pasteAutomationController: PasteAutomationController

    init(
        state: OnboardingState,
        pasteAutomationController: PasteAutomationController
    ) {
        self.state = state
        self.pasteAutomationController = pasteAutomationController
        let window = NSWindow()
        window.title = "Welcome to PasteList"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 480))
        window.minSize = NSSize(width: 620, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showIfNeeded() {
        guard state.shouldPresentOnLaunch else {
            return
        }
        show()
    }

    func show() {
        window?.contentViewController = NSHostingController(
            rootView: OnboardingView(
                state: state,
                pasteAutomationController: pasteAutomationController,
                onFinish: { [weak self] in
                    self?.close()
                }
            )
        )
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var pasteAutomationController: PasteAutomationController
    let onFinish: () -> Void

    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0:
                    welcomePage
                case 1:
                    shortcutPage
                case 2:
                    privacyPage
                default:
                    automaticPastePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                pageIndicator
                Spacer()
                if page > 0 {
                    Button("Back") {
                        page -= 1
                    }
                }
                Button(page == pageCount - 1 ? "Start Using PasteList" : "Continue") {
                    if page == pageCount - 1 {
                        state.complete()
                        onFinish()
                    } else {
                        page += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 480)
    }

    private var welcomePage: some View {
        onboardingPage(
            symbol: "menubar.rectangle",
            title: "Your clipboard, in the menu bar",
            message: "PasteList runs quietly in the menu bar. Click its icon whenever you want to browse your recent clipboard history."
        )
    }

    private var shortcutPage: some View {
        onboardingPage(
            symbol: "keyboard",
            title: "Open it from anywhere",
            message: "Press ⇧⌘V to open PasteList at the pointer. You can change this shortcut later in Settings.",
            badge: "⇧⌘V"
        )
    }

    private var privacyPage: some View {
        onboardingPage(
            symbol: "lock.shield",
            title: "Private by design",
            message: "Your clipboard history stays only on this Mac. PasteList has no account, cloud sync, analytics, or data transfer."
        )
    }

    private var automaticPastePage: some View {
        VStack(spacing: 22) {
            Image(systemName: pasteAutomationController.isPostEventAuthorized
                ? "checkmark.circle.fill"
                : "accessibility")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(pasteAutomationController.isPostEventAuthorized ? Color.green : Color.accentColor)
            Text("Optional automatic paste")
                .font(.system(size: 30, weight: .semibold))
            Text(
                "PasteList can return to the previous app and send only ⌘V after you choose an item. macOS lists this PostEvent permission under Accessibility, but PasteList does not read or control other apps’ interfaces."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)

            if pasteAutomationController.isPostEventAuthorized {
                Label("Automatic paste permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow Sending ⌘V") {
                    pasteAutomationController.requestAuthorization()
                }
                .controlSize(.large)
            }

            Text("You can skip this. PasteList will still copy the item, then you can press ⌘V manually.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(44)
    }

    private func onboardingPage(
        symbol: String,
        title: String,
        message: String,
        badge: String? = nil
    ) -> some View {
        VStack(spacing: 24) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)
            if let badge {
                Text(badge)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
        }
        .padding(44)
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Step \(page + 1) of \(pageCount)")
    }
}
