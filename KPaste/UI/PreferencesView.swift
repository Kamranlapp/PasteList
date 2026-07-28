import AppKit
import Carbon
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var hotKeyController: GlobalHotKeyController
    @ObservedObject var accessibilityController: AccessibilityController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    private let trustRefreshTimer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack {
                    Text("Open KPaste")
                    Spacer()
                    HotKeyRecorderField(
                        hotKey: hotKeyController.currentHotKey,
                        onRecord: { hotKeyController.updateHotKey($0) }
                    )
                    .frame(width: 150, height: 28)
                }

                if let error = hotKeyController.registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Automatic Paste") {
                HStack {
                    Label(
                        accessibilityController.isTrusted
                            ? "Accessibility access granted"
                            : "Accessibility access required",
                        systemImage: accessibilityController.isTrusted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        accessibilityController.isTrusted ? .green : .orange
                    )
                    Spacer()
                }

                HStack {
                    Button("Request Access") {
                        accessibilityController.requestAccess()
                    }
                    Button("Open System Settings") {
                        accessibilityController.openAccessibilitySettings()
                    }
                }
            }

            Section("History Retention") {
                LabeledContent("Maximum age", value: "7 days")
                LabeledContent("Maximum unpinned clips", value: "200")
                Text("Pinned clips are not removed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle(
                    "Launch KPaste at login",
                    isOn: Binding(
                        get: { launchAtLoginController.isEnabled },
                        set: { launchAtLoginController.setEnabled($0) }
                    )
                )
                Text(launchAtLoginController.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = launchAtLoginController.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 460, height: 360)
        .onAppear {
            accessibilityController.refreshTrust()
            launchAtLoginController.refresh()
        }
        .onReceive(trustRefreshTimer) { _ in
            accessibilityController.refreshTrust()
        }
    }
}

struct PreferencesContainerView: View {
    @ObservedObject var services: AppServices

    var body: some View {
        if
            let hotKeyController = services.globalHotKeyController,
            let accessibilityController = services.accessibilityController,
            let launchAtLoginController = services.launchAtLoginController
        {
            PreferencesView(
                hotKeyController: hotKeyController,
                accessibilityController: accessibilityController,
                launchAtLoginController: launchAtLoginController
            )
        } else {
            ProgressView()
                .frame(width: 460, height: 360)
        }
    }
}

private struct HotKeyRecorderField: NSViewRepresentable {
    let hotKey: HotKey
    let onRecord: (HotKey) -> Bool

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        HotKeyRecorderNSView(hotKey: hotKey, onRecord: onRecord)
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        nsView.hotKey = hotKey
        nsView.onRecord = onRecord
        nsView.updateLabel()
    }
}

private final class HotKeyRecorderNSView: NSView {
    var hotKey: HotKey
    var onRecord: (HotKey) -> Bool

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false

    init(hotKey: HotKey, onRecord: @escaping (HotKey) -> Bool) {
        self.hotKey = hotKey
        self.onRecord = onRecord
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateLabel()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        updateLabel()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            window?.makeFirstResponder(nil)
            updateLabel()
            return
        }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }

        let candidate = HotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        if onRecord(candidate) {
            hotKey = candidate
        } else {
            NSSound.beep()
        }
        isRecording = false
        window?.makeFirstResponder(nil)
        updateLabel()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateLabel()
        return super.resignFirstResponder()
    }

    func updateLabel() {
        label.stringValue = isRecording ? "Press shortcut…" : hotKey.displayName
        layer?.backgroundColor = (
            isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : NSColor.controlBackgroundColor
        ).cgColor
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }
}
