import Foundation
import GlassRecallCore

@main
struct GlassRecallToolsMain {
    static func main() async {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let docsDir = root.appendingPathComponent("docs", isDirectory: true)
            let screenshotsDir = docsDir.appendingPathComponent("screenshots", isDirectory: true)
            let graphsDir = docsDir.appendingPathComponent("graphs", isDirectory: true)
            let assetsDir = docsDir.appendingPathComponent("assets", isDirectory: true)
            let iconsetDir = root.appendingPathComponent(".build/AppIcon.iconset", isDirectory: true)

            print("[GlassRecallTools] Generating macOS AppIcon set...")
            try IconGenerator.generateIconSet(
                iconsetURL: iconsetDir,
                docsIconURL: assetsDir.appendingPathComponent("icon.png")
            )

            print("[GlassRecallTools] Rendering SwiftUI Retina screenshots...")
            try await MainActor.run {
                try ScreenshotRenderer.renderAll(outputDir: screenshotsDir)
            }

            print("[GlassRecallTools] Running Apple Silicon benchmark suite (1K -> 25K records)...")
            let report = try await BenchmarkRunner.runFullSuite(scaleLevels: [1_000, 5_000, 10_000, 25_000])

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(report)
            try jsonData.write(to: docsDir.appendingPathComponent("benchmarks.json"))

            print("[GlassRecallTools] Rendering benchmark graphs & architecture SVG...")
            try GraphRenderer.renderAll(report: report, outputDir: graphsDir)

            let summary = makeBenchmarkMarkdown(report: report)
            try summary.write(to: docsDir.appendingPathComponent("benchmark-summary.md"), atomically: true, encoding: .utf8)

            print("[GlassRecallTools] Complete!")
            print(summary)
        } catch {
            fputs("[GlassRecallTools] ERROR: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func makeBenchmarkMarkdown(report: BenchmarkReport) -> String {
        var rows = ""
        for pt in report.scalePoints {
            let mb = Double(pt.databaseBytes) / (1024.0 * 1024.0)
            rows += String(
                format: "| %d | %.2f MB | %.0f B | **%.2f ms** | **%.2f ms** |\n",
                pt.recordCount, mb, pt.bytesPerMemory, pt.searchP50Ms, pt.searchP95Ms
            )
        }

        let glassGB = report.projected30DayGlassRecallMB / 1024.0
        let reduction = report.projected30DayRawPNGGB / max(glassGB, 0.001)

        return """
        ### Measured Benchmarks (\(report.hostArchitecture) · \(report.osVersion))

        - **Frame-Diff Gate:** `\(String(format: "%.2f ms", report.frameDiffAvgMs))` avg evaluation · `\(String(format: "%.1f%%", report.frameDiffSkipRatePercent))` static frames dropped before OCR
        - **Apple Vision OCR:** `\(String(format: "%.1f ms", report.visionOCRAvgMs))` avg per changed 1280×800 frame · `\(String(format: "%.1f%%", report.visionOCRWordRecallPercent))` verified token recall
        - **Secret Redactor:** `\(String(format: "%.2f ms", report.sanitizerAvgMs))` avg · `\(report.sanitizerSecretsCaught)/4` injected credential types scrubbed
        - **30-Day Storage (47,520 memories):** **`\(String(format: "%.1f MB", report.projected30DayGlassRecallMB))`** vs `\(String(format: "%.1f GB", report.projected30DayRawPNGGB))` raw PNG (**`\(String(format: "%.0fx", reduction))` smaller**)

        | Indexed Memories | SQLite WAL Size | Bytes / Memory | Hybrid Search p50 | Hybrid Search p95 |
        | ---: | ---: | ---: | ---: | ---: |
        \(rows)
        """
    }
}
