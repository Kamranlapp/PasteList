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
        window.setContentSize(NSSize(width: 640, height: 480))
        window.minSize = NSSize(width: 640, height: 480)
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
    @State private var isAwaitingPulse = false

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
                    .fixedSize()
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
                .fixedSize()
            }
            .padding(20)
        }
        .frame(width: 640, height: 480)
        .onAppear {
            pasteAutomationController.refreshAuthorization()
        }
        .onChange(of: pasteAutomationController.isPostEventAuthorized) { isAuthorized in
            guard isAuthorized, page == 0 else { return }
            Task {
                try? await Task.sleep(nanoseconds: 650_000_000)
                withAnimation {
                    page = 1
                }
            }
        }
        .onChange(of: pasteAutomationController.permissionRequestState) { newState in
            if newState == .awaitingSystemApproval {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    isAwaitingPulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAwaitingPulse = false
                }
            }
        }
    }

    private var accessibilityPage: some View {
        VStack(spacing: 22) {
            Image(systemName: pasteAutomationController.isPostEventAuthorized
                ? "checkmark.circle.fill"
                : "accessibility")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(pasteAutomationController.isPostEventAuthorized ? Color.green : Color.accentColor)
                .scaleEffect(isAwaitingPulse ? 1.08 : 1.0)
            Text("Let PasteList paste for you")
                .font(.system(size: 30, weight: .semibold))

            if pasteAutomationController.isPostEventAuthorized {
                Label("Automatic paste permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 12) {
                    Button("Give Access") {
                        Task {
                            await pasteAutomationController.requestAuthorization()
                        }
                    }
                    .disabled(
                        pasteAutomationController.permissionRequestState == .requesting
                    )

                    if pasteAutomationController.permissionRequestState == .requesting
                        || pasteAutomationController.permissionRequestState == .awaitingSystemApproval {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for approval…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("You can skip this and paste manually with ⌘V.")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
