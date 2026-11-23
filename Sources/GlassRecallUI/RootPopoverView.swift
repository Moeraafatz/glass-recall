import AppKit
import GlassRecallCore
import SwiftUI

public struct RootPopoverView: View {
    @Bindable var state: AppState
    public let width: CGFloat

    public init(state: AppState, width: CGFloat = 500) {
        self.state = state
        self.width = width
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer

            VStack(spacing: 11) {
                headerBar
                tabSelector

                Group {
                    switch state.selectedTab {
                    case .search:
                        SearchView(state: state)
                    case .timeline:
                        TimelineView(state: state)
                    case .insights:
                        InsightsView(state: state)
                    case .privacy:
                        PrivacyView(state: state)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                footerBar
            }
            .padding(14)

            if let toast = state.statusToast {
                Text(toast)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GlassTheme.emerald))
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(GlassTheme.cardBorderStrong, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [GlassTheme.canvasTop, GlassTheme.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [GlassTheme.cyan.opacity(0.16), Color.clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 340
            )
            RadialGradient(
                colors: [GlassTheme.emerald.opacity(0.11), Color.clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 300
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GlassTheme.cyan.opacity(0.32), GlassTheme.emerald.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(GlassTheme.cyan.opacity(0.55), lineWidth: 1)
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GlassTheme.cyan)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Glass Recall")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlassTheme.textPrimary)
                    Text("v1.0.0")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GlassTheme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                Text("Zero-Cloud Screen Memory · 0 B Raw Images")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GlassTheme.textSecondary)
            }

            Spacer()

            Button {
                state.toggleCapture()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(captureStatusColor)
                        .frame(width: 7, height: 7)
                    Text(captureStatusLabel)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(captureStatusColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(captureStatusColor.opacity(0.14))
                        .overlay(Capsule().strokeBorder(captureStatusColor.opacity(0.35), lineWidth: 0.75))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var captureStatusColor: Color {
        if state.stats.pausedUntil != nil { return GlassTheme.amber }
        return state.stats.isCapturing ? GlassTheme.emerald : GlassTheme.textTertiary
    }

    private var captureStatusLabel: String {
        if state.stats.pausedUntil != nil { return "Paused" }
        return state.stats.isCapturing ? "Live" : "Stopped"
    }

    private var tabSelector: some View {
        let tabs = RecallTab.allCases
        return HStack(spacing: 5) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let active = state.selectedTab == tab
                Button {
                    state.selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: active ? .bold : .medium))
                        Text(tab.shortcut)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(active ? Color.black.opacity(0.65) : GlassTheme.textTertiary)
                    }
                    .foregroundStyle(active ? Color.black : GlassTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6.5)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? GlassTheme.textPrimary : Color.white.opacity(0.055))
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Text("⌥Space Toggle HUD")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(GlassTheme.textTertiary)
            Text("·")
                .foregroundStyle(GlassTheme.textTertiary)
            Text("SQLite \(GlassTheme.formatBytes(state.stats.databaseBytes))")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(GlassTheme.textSecondary)
            Spacer()
            Text("100% Offline")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(GlassTheme.emerald.opacity(0.9))
            if !state.isPreviewSnapshot {
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(GlassTheme.textTertiary)
            }
        }
        .padding(.top, 2)
    }
}
