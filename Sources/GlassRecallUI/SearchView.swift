import GlassRecallCore
import SwiftUI

public struct SearchView: View {
    @Bindable var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 10) {
            searchInputBar
            filterRow
            resultsSection
        }
    }

    private var searchInputBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GlassTheme.cyan)

            if state.isPreviewSnapshot {
                HStack(spacing: 2) {
                    Text(state.queryText.isEmpty ? "Search anything you saw on screen…" : state.queryText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(state.queryText.isEmpty ? GlassTheme.textTertiary : GlassTheme.textPrimary)
                    Rectangle()
                        .fill(GlassTheme.cyan)
                        .frame(width: 1.5, height: 15)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Search anything you saw on screen…", text: $state.queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GlassTheme.textPrimary)
                    .onChange(of: state.queryText) { _, _ in
                        state.triggerSearch()
                    }
            }

            if !state.queryText.isEmpty {
                Text(String(format: "%.1f ms", max(0.4, state.stats.lastSearchMs)))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GlassTheme.emerald)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(GlassTheme.emerald.opacity(0.14)))

                if !state.isPreviewSnapshot {
                    Button {
                        state.queryText = ""
                        state.triggerSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(GlassTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GlassTheme.cyan.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(DateRangeFilter.allCases) { range in
                let active = state.dateRange == range
                Button {
                    state.dateRange = range
                    state.triggerSearch()
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Color.black : GlassTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(active ? GlassTheme.cyan : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            if let selectedApp = state.selectedAppFilter {
                Button {
                    state.selectedAppFilter = nil
                    state.triggerSearch()
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedApp)
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(GlassTheme.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(GlassTheme.amber.opacity(0.16)))
                }
                .buttonStyle(.plain)
            } else {
                Text("\(state.hits.count) matches · Hybrid FTS5+Vec")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(GlassTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if state.hits.isEmpty {
            GlassCard(padding: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 24))
                        .foregroundStyle(GlassTheme.cyan.opacity(0.75))
                    Text("No matching screen memories yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GlassTheme.textPrimary)
                    Text("Glass Recall indexes changed windows locally via Vision OCR without saving raw screenshots.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(GlassTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        } else if state.isPreviewSnapshot {
            VStack(spacing: 8) {
                ForEach(state.hits.prefix(4)) { hit in
                    hitRow(hit)
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(state.hits) { hit in
                        hitRow(hit)
                    }
                }
            }
            .frame(maxHeight: 375)
        }
    }

    private func hitRow(_ hit: SearchHit) -> some View {
        let tint = GlassTheme.appTint(for: hit.record.appName)
        return GlassCard(padding: 10, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: GlassTheme.appSymbol(for: hit.record.appName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.16)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.record.windowTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GlassTheme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(hit.record.appName)
                                .foregroundStyle(tint)
                            Text("·")
                                .foregroundStyle(GlassTheme.textTertiary)
                            Text(relativeTime(hit.record.timestamp))
                                .foregroundStyle(GlassTheme.textTertiary)
                            if hit.record.redactedSecrets > 0 {
                                Label("\(hit.record.redactedSecrets) redacted", systemImage: "lock.shield.fill")
                                    .foregroundStyle(GlassTheme.amber)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                    }

                    Spacer(minLength: 4)

                    Text("\(Int((hit.combinedScore * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(GlassTheme.emerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(GlassTheme.emerald.opacity(0.15)))
                }

                Text(hit.snippet)
                    .font(.system(size: 11.2, design: .monospaced))
                    .foregroundStyle(GlassTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(hit.record.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tag == "redacted" ? GlassTheme.amber : GlassTheme.cyan.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }

                    Spacer()

                    Button {
                        state.copyText(hit.record.text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(GlassTheme.textPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    if let url = hit.record.url, url.hasPrefix("http") {
                        Button {
                            state.openURL(url)
                        } label: {
                            Label("Open", systemImage: "arrow.up.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(GlassTheme.cyan)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(GlassTheme.cyan.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        if secs < 60 { return "\(secs)s ago" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}
