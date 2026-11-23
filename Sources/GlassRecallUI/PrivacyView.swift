import GlassRecallCore
import SwiftUI

public struct PrivacyView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 10) {
            permissionsCard
            protectionsCard
            blocklistCard
            panicControlsCard
        }
    }

    private var permissionsCard: some View {
        GlassCard(padding: 11, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Local macOS Permissions (Zero Root · Zero Network)", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(GlassTheme.textPrimary)

                permissionRow(
                    title: "Screen Recording",
                    detail: "Required for in-RAM diff & Vision OCR (pixels discarded instantly)",
                    granted: state.hasScreenPermission,
                    actionLabel: "Grant",
                    action: { state.requestScreenPermission() }
                )

                Divider().overlay(Color.white.opacity(0.08))

                permissionRow(
                    title: "Accessibility (Optional)",
                    detail: "Adds exact window titles & document URLs to search index",
                    granted: state.hasAccessibilityPermission,
                    actionLabel: "Enable",
                    action: { state.openAccessibilitySettings() }
                )
            }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(granted ? GlassTheme.emerald : GlassTheme.amber)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(GlassTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 9.8))
                    .foregroundStyle(GlassTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if granted {
                Text("Active")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(GlassTheme.emerald)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(GlassTheme.emerald.opacity(0.14)))
            } else {
                Button(actionLabel, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(GlassTheme.amber))
            }
        }
    }

    private var protectionsCard: some View {
        GlassCard(padding: 11, cornerRadius: 14) {
            VStack(spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Secret Redaction")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(GlassTheme.textPrimary)
                        Text("Scrubs API keys, JWTs, AWS/GitHub tokens & passwords before SQLite write")
                            .font(.system(size: 9.8))
                            .foregroundStyle(GlassTheme.textSecondary)
                    }
                    Spacer()
                    GlassTogglePill(isOn: state.config.redactSecrets, accent: GlassTheme.emerald) {
                        state.updateConfig { $0.redactSecrets.toggle() }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Retention Window")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(GlassTheme.textPrimary)
                        Text("Auto-prunes memories older than selected window")
                            .font(.system(size: 9.8))
                            .foregroundStyle(GlassTheme.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([7, 30, 90, 0], id: \.self) { days in
                            let selected = state.config.retentionDays == days
                            Button {
                                state.updateConfig { $0.retentionDays = days }
                            } label: {
                                Text(days == 0 ? "∞" : "\(days)d")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(selected ? Color.black : GlassTheme.textSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(Capsule().fill(selected ? GlassTheme.cyan : Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var blocklistCard: some View {
        GlassCard(padding: 11, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Hard Privacy Exclusions (Pre-Capture Gate)", systemImage: "eye.slash.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(GlassTheme.textPrimary)
                    Spacer()
                    Text("\(state.stats.framesBlockedByPrivacy) blocked")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GlassTheme.amber)
                }

                HStack(spacing: 5) {
                    ForEach(["1Password", "Passwords", "Keychain", "Incognito", "Private Browsing"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(GlassTheme.textPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
                            )
                    }
                }
            }
        }
    }

    private var panicControlsCard: some View {
        GlassCard(padding: 11, cornerRadius: 14, borderColor: GlassTheme.rose.opacity(0.32)) {
            HStack(spacing: 8) {
                Button {
                    state.pauseCapture(minutes: 15)
                } label: {
                    Label("Pause 15m", systemImage: "pause.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GlassTheme.amber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(GlassTheme.amber.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Button {
                    state.purgeRecent(minutes: 15)
                } label: {
                    Label("Purge Last 15m", systemImage: "flame.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GlassTheme.rose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(GlassTheme.rose.opacity(0.16)))
                }
                .buttonStyle(.plain)

                Button {
                    state.wipeAllMemories()
                } label: {
                    Label("Wipe DB", systemImage: "trash.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(GlassTheme.rose.opacity(0.65)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
