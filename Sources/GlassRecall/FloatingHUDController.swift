import AppKit
@preconcurrency import Carbon
import GlassRecallUI
import SwiftUI

private enum HotKeyTrampoline {
    nonisolated(unsafe) static var handler: (@Sendable () -> Void)?
}

private func carbonHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    HotKeyTrampoline.handler?()
    return noErr
}

@MainActor
final class FloatingHUDController {
    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let state: AppState

    init(state: AppState) {
        self.state = state
        registerGlobalHotKey()
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        show()
    }

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: RootPopoverView(state: state, width: 520))
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 610),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isMovableByWindowBackground = true
            newPanel.contentView = hosting
            panel = newPanel
        }

        guard let panel else { return }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            let x = visible.midX - size.width / 2
            let y = visible.maxY - size.height - 90
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Task {
            await state.reloadAll()
        }
    }

    private func registerGlobalHotKey() {
        HotKeyTrampoline.handler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggle()
            }
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4752434C), id: 1) // "GRCL"
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
