import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public enum ContextInspector {
    public static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked {
            return true
        }
        if let onConsole = dict["kCGSSessionOnConsoleKey"] as? Bool, !onConsole {
            return true
        }
        return false
    }

    @MainActor
    public static func currentWindowContext() -> WindowContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let appName = app.localizedName ?? "Unknown App"
        let bundleID = app.bundleIdentifier ?? ""
        let pid = app.processIdentifier

        var title = ""
        var documentURL: String?

        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedWindowRef: CFTypeRef?
            let winStatus = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
            if winStatus == .success, let rawWin = focusedWindowRef {
                let winElement = rawWin as! AXUIElement
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(winElement, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let str = titleRef as? String {
                    title = str
                }
                var docRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(winElement, kAXDocumentAttribute as CFString, &docRef) == .success,
                   let docStr = docRef as? String, !docStr.isEmpty {
                    documentURL = docStr
                }
            }
        }

        if title.isEmpty {
            title = appName
        }

        return WindowContext(
            appName: appName,
            bundleID: bundleID,
            windowTitle: title,
            url: documentURL,
            processID: pid
        )
    }
}
