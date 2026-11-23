import GlassRecallCore
import SwiftUI

public struct InsightsView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 10) {
            metricGrid
            storageSavingsCard
            appBreakdownCard
        }
    }

    private var metricGrid: some View {
        HStack(spacing: 8) {
            statTile(
                title: "INDEXED",
                value: formatNumber(state.stats.totalMemories),
                sub: "Text + 128-d Vec",
                accent: GlassTheme.cyan
            )
            statTile(
                title: "DIFF-SKIPPED",
                value: String(format: "%.1f%%", state.stats.skipRatePercent),
                sub: "\(formatNumber(state.stats.framesSkippedByDiff)) static drops",
                accent: GlassTheme.emerald
            )
            statTile(
                title: "AVG OCR",
                value: String(format: "%.0f ms", state.stats.averageOcrMs),
                sub: "Apple Vision ANE",
                accent: GlassTheme.indigo
            )
            statTile(
                title: "REDACTED",
                value: "\(state.stats.secretsRedacted)",
                sub: "Keys scrubbed",
                accent: GlassTheme.amber
            )
        }
    }

    private func statTile(title: String, value: String, sub: String, accent: Color) -> some View {
        GlassCard(padding: 9, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(GlassTheme.textTertiary)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(sub)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GlassTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var storageSavingsCard: some View {
        let rawBytes = max(state.stats.estimatedRawScreenshotsBytes, 1)
        let dbBytes = max(state.stats.databaseBytes, 1)
        let reduction = max(0.0, (1.0 - (Double(dbBytes) / Double(rawBytes))) * 100.0)
        let dbBarFraction = max(0.025, min(1.0, Double(dbBytes) / Double(rawBytes)))

        return GlassCard(padding: 12, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Zero-Image Storage Compression", systemImage: "internaldrive.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(GlassTheme.textPrimary)
                    Spacer()
                    Text(String(format: "%.2f%% smaller", reduction))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(GlassTheme.emerald)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(GlassTheme.emerald.opacity(0.15)))
                }

                storageBarRow(
                    label: "Glass Recall SQLite (Text + FTS5 + Vectors)",
                    value: GlassTheme.formatBytes(dbBytes),
                    fraction: dbBarFraction,
                    color: GlassTheme.emerald
                )
                storageBarRow(
                    label: "Equivalent Raw Retina Screenshots (Not Saved)",
                    value: GlassTheme.formatBytes(rawBytes),
                    fraction: 1.0,
                    color: GlassTheme.rose.opacity(0.65)
                )
            }
        }
    }

    private func storageBarRow(label: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GlassTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(GlassTheme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: max(8, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 7)
        }
    }

    private var appBreakdownCard: some View {
        let maxCount = max(state.appBuckets.map(\.count).max() ?? 1, 1)
        return GlassCard(padding: 12, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Memory Distribution by App", systemImage: "square.grid.2x2.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(GlassTheme.textPrimary)
                    Spacer()
                    Text("Click app to filter")
                        .font(.system(size: 9.5))
                        .foregroundStyle(GlassTheme.textTertiary)
                }

                ForEach(state.appBuckets.prefix(6)) { bucket in
                    let tint = GlassTheme.appTint(for: bucket.appName)
                    let frac = Double(bucket.count) / Double(maxCount)
                    Button {
                        state.selectedAppFilter = bucket.appName
                        state.selectedTab = .search
                        state.triggerSearch()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: GlassTheme.appSymbol(for: bucket.appName))
                                .font(.system(size: 10))
                                .foregroundStyle(tint)
                                .frame(width: 16)
                            Text(bucket.appName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(GlassTheme.textPrimary)
                                .frame(width: 72, alignment: .leading)
                                .lineLimit(1)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.06))
                                    Capsule().fill(tint.opacity(0.85))
                                        .frame(width: max(6, geo.size.width * CGFloat(frac)))
                                }
                            }
                            .frame(height: 6)

                            Text(formatNumber(bucket.count))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(GlassTheme.textSecondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
}
