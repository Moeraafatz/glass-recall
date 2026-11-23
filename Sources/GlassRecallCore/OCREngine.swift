import CoreGraphics
import Foundation
@preconcurrency import Vision

public struct OCRResult: Sendable {
    public let text: String
    public let lineCount: Int
    public let averageConfidence: Double
    public let durationMs: Double

    public init(text: String, lineCount: Int, averageConfidence: Double, durationMs: Double) {
        self.text = text
        self.lineCount = lineCount
        self.averageConfidence = averageConfidence
        self.durationMs = durationMs
    }
}

public enum OCREngine {
    public static func recognize(image: CGImage, fastMode: Bool = false) throws -> OCRResult {
        let start = CFAbsoluteTimeGetCurrent()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fastMode ? .fast : .accurate
        request.usesLanguageCorrection = !fastMode
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        var lines: [String] = []
        lines.reserveCapacity(observations.count)
        var confidenceSum: Double = 0

        for obs in observations {
            if let candidate = obs.topCandidates(1).first {
                let s = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty {
                    lines.append(s)
                    confidenceSum += Double(candidate.confidence)
                }
            }
        }

        let avgConf = lines.isEmpty ? 0.0 : confidenceSum / Double(lines.count)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        return OCRResult(
            text: lines.joined(separator: "\n"),
            lineCount: lines.count,
            averageConfidence: avgConf,
            durationMs: elapsed
        )
    }
}
