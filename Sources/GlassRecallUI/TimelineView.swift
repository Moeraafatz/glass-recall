import GlassRecallCore
import SwiftUI

public struct TimelineView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 10) {
            activityPulseCard
            timelineStream
        }
    }

    private var activityPulseCard: some View {
        let maxCount = max(state.hourlyActivity.map(\.count).max() ?? 1, 1)
        return GlassCard(padding: 12, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("12-Hour Capture Density", systemImage: "waveform.path.ecg")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(GlassTheme.textPrimary)
                    Spacer()
                    Text("\(state.hourlyActivity.reduce(0) { $0 + $1.count }) changed frames")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(GlassTheme.cyan)
                }

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(state.hourlyActivity) { point in
                        let ratio = max(0.08, Double(point.count) / Double(maxCount))
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [GlassTheme.cyan, GlassTheme.emerald.opacity(0.75)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: CGFloat(ratio * 46.0))
                            Text(String(format: "%02d", point.hour))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(GlassTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 60, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private var timelineStream: some View {
        if state.isPreviewSnapshot {
            VStack(spacing: 7) {
                ForEach(state.recentRecords.prefix(5)) { rec in
                    timelineRow(rec)
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(state.recentRecords) { rec in
                        timelineRow(rec)
                    }
                }
            }
            .frame(maxHeight: 335)
        }
    }

    private func timelineRow(_ rec: MemoryRecord) -> some View {
        let tint = GlassTheme.appTint(for: rec.appName)
        return GlassCard(padding: 9, cornerRadius: 12) {
            HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 3) {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1.5, height: 34)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rec.appName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                        Text("·")
                            .foregroundStyle(GlassTheme.textTertiary)
                        Text(rec.windowTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GlassTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(shortClock(rec.timestamp))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(GlassTheme.textTertiary)
                    }

                    Text(rec.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10.8, design: .monospaced))
                        .foregroundStyle(GlassTheme.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(String(format: "OCR %.0f ms", rec.ocrDurationMs))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(GlassTheme.textTertiary)
                        if rec.redactedSecrets > 0 {
                            Text("· \(rec.redactedSecrets) secret redacted")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(GlassTheme.amber)
                        }
                        Spacer()
                        Button("Copy") {
                            state.copyText(rec.text)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GlassTheme.cyan)
                    }
                }
            }
        }
    }

    private func shortClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
