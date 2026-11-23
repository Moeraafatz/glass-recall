import AppKit
import CoreGraphics
import Foundation
import GlassRecallUI
import SwiftUI

@MainActor
enum ScreenshotRenderer {
    static func renderAll(outputDir: URL) throws {
        // Initialize AppKit context safely for headless CI rendering
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let searchImg = try renderCard(tab: .search, query: "sqlite wal fts5")
        let timelineImg = try renderCard(tab: .timeline, query: "")
        let insightsImg = try renderCard(tab: .insights, query: "")
        let privacyImg = try renderCard(tab: .privacy, query: "")

        try IconGenerator.writePNG(searchImg, to: outputDir.appendingPathComponent("search.png"))
        try IconGenerator.writePNG(timelineImg, to: outputDir.appendingPathComponent("timeline.png"))
        try IconGenerator.writePNG(insightsImg, to: outputDir.appendingPathComponent("insights.png"))
        try IconGenerator.writePNG(privacyImg, to: outputDir.appendingPathComponent("privacy.png"))

        let hero = try renderHeroBanner(search: searchImg, insights: insightsImg, privacy: privacyImg)
        try IconGenerator.writePNG(hero, to: outputDir.appendingPathComponent("hero.png"))
    }

    private static func renderCard(tab: RecallTab, query: String) throws -> CGImage {
        let state = AppState.demo(tab: tab, query: query)
        let framed = RootPopoverView(state: state, width: 510)
            .padding(24)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.04, blue: 0.06),
                        Color(red: 0.015, green: 0.02, blue: 0.032)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2.0
        guard let cg = renderer.cgImage else {
            throw NSError(domain: "GlassRecallTools.Screenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "ImageRenderer returned nil for tab \(tab.rawValue)"])
        }
        return cg
    }

    private static func renderHeroBanner(search: CGImage, insights: CGImage, privacy: CGImage) throws -> CGImage {
        let heroView = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.032, blue: 0.052),
                    Color(red: 0.012, green: 0.018, blue: 0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [GlassTheme.cyan.opacity(0.20), Color.clear],
                center: UnitPoint(x: 0.22, y: 0.18),
                startRadius: 20,
                endRadius: 560
            )
            RadialGradient(
                colors: [GlassTheme.emerald.opacity(0.16), Color.clear],
                center: UnitPoint(x: 0.80, y: 0.82),
                startRadius: 20,
                endRadius: 540
            )

            VStack(spacing: 26) {
                HStack(spacing: 12) {
                    Text("GLASS RECALL")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(GlassTheme.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(GlassTheme.cyan.opacity(0.14))
                                .overlay(Capsule().strokeBorder(GlassTheme.cyan.opacity(0.45), lineWidth: 1))
                        )
                    Text("Instant Hybrid Search · Live Efficiency Insights · Hard Privacy Gate")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GlassTheme.textSecondary)
                }

                HStack(alignment: .center, spacing: 24) {
                    panelPreview(image: search, caption: "Instant Hybrid Recall (⌘1)")
                    panelPreview(image: insights, caption: "Diff-Gate & Storage Savings (⌘3)")
                    panelPreview(image: privacy, caption: "Zero-Cloud Privacy Gate (⌘4)")
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
        }
        .frame(width: 1640, height: 860)
        .preferredColorScheme(.dark)

        let renderer = ImageRenderer(content: heroView)
        renderer.scale = 2.0
        guard let cg = renderer.cgImage else {
            throw NSError(domain: "GlassRecallTools.Screenshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to render hero banner"])
        }
        return cg
    }

    private static func panelPreview(image: CGImage, caption: String) -> some View {
        VStack(spacing: 10) {
            Image(decorative: image, scale: 2.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 495)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.65), radius: 24, x: 0, y: 14)

            Text(caption)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(GlassTheme.textSecondary)
        }
    }
}
