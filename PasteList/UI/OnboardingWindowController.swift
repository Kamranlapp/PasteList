import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    private let state: OnboardingState
    private let pasteAutomationController: PasteAutomationController
    private let globalHotKeyController: GlobalHotKeyController

    init(
        state: OnboardingState,
        pasteAutomationController: PasteAutomationController,
        globalHotKeyController: GlobalHotKeyController
    ) {
        self.state = state
        self.pasteAutomationController = pasteAutomationController
        self.globalHotKeyController = globalHotKeyController
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
        guard AppConfiguration.isOnboardingEnabled, state.shouldPresentOnLaunch else {
            return
        }
        show()
    }

    func show() {
        guard AppConfiguration.isOnboardingEnabled else {
            return
        }
        window?.contentViewController = NSHostingController(
            rootView: OnboardingView(
                state: state,
                pasteAutomationController: pasteAutomationController,
                globalHotKeyController: globalHotKeyController,
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
    @ObservedObject var globalHotKeyController: GlobalHotKeyController
    let onFinish: () -> Void

    @State private var page = 0

    private let pageCount = 2

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0:
                    accessibilityPage
                default:
                    shortcutPage
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
        .onAppear {
            pasteAutomationController.refreshAuthorization()
        }
    }

    private var accessibilityPage: some View {
        VStack(spacing: 22) {
            Image(systemName: pasteAutomationController.isPostEventAuthorized
                ? "checkmark.circle.fill"
                : "accessibility")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(pasteAutomationController.isPostEventAuthorized ? Color.green : Color.accentColor)
            Text("Let PasteList paste for you")
                .font(.system(size: 30, weight: .semibold))
            Text(
                "After you pick a clip, PasteList can jump back to your previous app and press ⌘V for you. macOS lists this PostEvent permission under Accessibility, but PasteList does not read or control other apps’ interfaces."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)

            if pasteAutomationController.isPostEventAuthorized {
                Label("Automatic paste permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Give Access") {
                            Task {
                                await pasteAutomationController.requestAuthorization()
                            }
                        }
                        .disabled(
                            pasteAutomationController.permissionRequestState == .requesting
                        )

                        if pasteAutomationController.permissionRequestState == .requesting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Requesting permission…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if pasteAutomationController.permissionRequestState == .awaitingSystemApproval {
                        VStack(spacing: 6) {
                            Text("Waiting for macOS approval. Use the system permission alert; do not add PasteList manually.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Open System Settings") {
                                pasteAutomationController.openPostEventSettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
            }

            Text("You can skip this. PasteList will still copy the item, then you can press ⌘V manually — and you can grant access later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(44)
    }

    private var shortcutPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("Open it from anywhere")
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(.center)

            HotKeyRecorderField(
                hotKey: globalHotKeyController.currentHotKey,
                onRecord: { globalHotKeyController.updateHotKey($0) }
            )
            .frame(width: 150, height: 32)

            if let error = globalHotKeyController.registrationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Press this shortcut to open PasteList at the pointer. Click the field above to record a different one — you can also change it later in Settings.")
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
