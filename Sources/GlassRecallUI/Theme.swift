import SwiftUI

public enum GlassTheme {
    public static let canvasTop = Color(red: 0.045, green: 0.055, blue: 0.075)
    public static let canvasBottom = Color(red: 0.025, green: 0.032, blue: 0.045)
    public static let cardSurface = Color.white.opacity(0.055)
    public static let cardElevated = Color.white.opacity(0.085)
    public static let cardBorder = Color.white.opacity(0.11)
    public static let cardBorderStrong = Color.white.opacity(0.18)

    public static let emerald = Color(red: 0.188, green: 0.820, blue: 0.345)   // #30D158
    public static let cyan = Color(red: 0.392, green: 0.824, blue: 1.000)      // #64D2FF
    public static let amber = Color(red: 1.000, green: 0.624, blue: 0.039)     // #FF9F0A
    public static let rose = Color(red: 1.000, green: 0.271, blue: 0.227)      // #FF453A
    public static let indigo = Color(red: 0.486, green: 0.451, blue: 0.988)

    public static let textPrimary = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.64)
    public static let textTertiary = Color.white.opacity(0.42)

    public static func appTint(for appName: String) -> Color {
        switch appName.lowercased() {
        case let s where s.contains("xcode"): return cyan
        case let s where s.contains("terminal") || s.contains("iterm") || s.contains("ghostty"): return emerald
        case let s where s.contains("safari") || s.contains("chrome") || s.contains("arc"): return indigo
        case let s where s.contains("zoom") || s.contains("meet"): return Color(red: 0.23, green: 0.56, blue: 1.0)
        case let s where s.contains("stripe") || s.contains("preview") || s.contains("pdf"): return amber
        case let s where s.contains("slack"): return Color(red: 0.88, green: 0.36, blue: 0.58)
        default: return Color.white.opacity(0.72)
        }
    }

    public static func appSymbol(for appName: String) -> String {
        switch appName.lowercased() {
        case let s where s.contains("xcode") || s.contains("code"): return "hammer.fill"
        case let s where s.contains("terminal") || s.contains("iterm") || s.contains("ghostty"): return "terminal.fill"
        case let s where s.contains("safari") || s.contains("chrome") || s.contains("arc"): return "globe"
        case let s where s.contains("zoom") || s.contains("meet"): return "video.fill"
        case let s where s.contains("preview") || s.contains("pdf"): return "doc.richtext.fill"
        case let s where s.contains("slack"): return "bubble.left.and.bubble.right.fill"
        case let s where s.contains("obsidian") || s.contains("notes"): return "note.text"
        default: return "macwindow"
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0
        let val = Double(bytes)
        if val >= gb { return String(format: "%.2f GB", val / gb) }
        if val >= mb { return String(format: "%.1f MB", val / mb) }
        if val >= kb { return String(format: "%.0f KB", val / kb) }
        return "\(bytes) B"
    }
}

public struct GlassCard<Content: View>: View {
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let borderColor: Color
    private let content: Content

    public init(
        padding: CGFloat = 12,
        cornerRadius: CGFloat = 14,
        borderColor: Color = GlassTheme.cardBorder,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GlassTheme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
    }
}

public struct GlassTogglePill: View {
    public let isOn: Bool
    public let accent: Color
    public let action: () -> Void

    public init(isOn: Bool, accent: Color = GlassTheme.emerald, action: @escaping () -> Void) {
        self.isOn = isOn
        self.accent = accent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? accent.opacity(0.85) : Color.white.opacity(0.14))
                    .frame(width: 34, height: 19)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}
