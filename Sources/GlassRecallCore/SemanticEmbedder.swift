import Accelerate
import Foundation
import NaturalLanguage

public final class SemanticEmbedder: @unchecked Sendable {
    public static let dimensions = 128

    private let lock = NSLock()
    private var sentenceEmbeddingLoaded = false
    private var nlEmbedding: NLEmbedding?

    public init() {}

    private func loadNLEmbeddingIfAvailable() -> NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if !sentenceEmbeddingLoaded {
            sentenceEmbeddingLoaded = true
            nlEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        }
        return nlEmbedding
    }

    public func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: Self.dimensions)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return vector }

        // 1. Deterministic token + character-trigram signed feature hashing (catches code, errors, URLs, product names)
        let hashVec = Self.hashedFeatures(for: trimmed)
        for i in 0..<Self.dimensions {
            vector[i] += hashVec[i]
        }

        // 2. Blend Apple NaturalLanguage offline sentence embedding when available on host macOS
        if let model = loadNLEmbeddingIfAvailable() {
            let prefix = String(trimmed.prefix(512))
            if let nlVec = model.vector(for: prefix), !nlVec.isEmpty {
                var folded = [Float](repeating: 0, count: Self.dimensions)
                for (idx, val) in nlVec.enumerated() {
                    let bucket = idx % Self.dimensions
                    let sign: Float = ((idx / Self.dimensions) % 2 == 0) ? 1.0 : -1.0
                    folded[bucket] += Float(val) * sign
                }
                Self.normalizeInPlace(&folded)
                for i in 0..<Self.dimensions {
                    vector[i] = 0.55 * folded[i] + 0.45 * vector[i]
                }
            }
        }

        Self.normalizeInPlace(&vector)
        return vector
    }

    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return max(0, min(1, dot))
    }

    public static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
    }

    public static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        guard count == dimensions else { return [Float](repeating: 0, count: dimensions) }
        var result = [Float](repeating: 0, count: count)
        _ = result.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst)
        }
        return result
    }

    private static func hashedFeatures(for text: String) -> [Float] {
        var vec = [Float](repeating: 0, count: dimensions)
        let lower = text.lowercased()
        let tokens = lower.split { !$0.isLetter && !$0.isNumber && $0 != "_" }

        for tokenSub in tokens {
            let token = String(tokenSub)
            guard token.count >= 2 else { continue }
            addFeature(token, weight: 1.5, to: &vec)

            // Character 3-grams for morphological / prefix / typo resilience
            let chars = Array(token)
            if chars.count >= 4 {
                let maxTrigrams = min(chars.count - 2, 12)
                for i in 0..<maxTrigrams {
                    let trigram = String(chars[i..<(i + 3)])
                    addFeature("#" + trigram, weight: 0.45, to: &vec)
                }
            }
        }

        // Word bigrams for short phrase intent
        if tokens.count >= 2 {
            let maxBigrams = min(tokens.count - 1, 64)
            for i in 0..<maxBigrams {
                addFeature("\(tokens[i])_\(tokens[i + 1])", weight: 1.0, to: &vec)
            }
        }

        normalizeInPlace(&vec)
        return vec
    }

    private static func addFeature(_ feature: String, weight: Float, to vec: inout [Float]) {
        // FNV-1a 64-bit deterministic hash
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in feature.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let bucket = Int(hash % UInt64(dimensions))
        let sign: Float = ((hash >> 63) == 0) ? 1.0 : -1.0
        vec[bucket] += sign * weight
    }

    private static func normalizeInPlace(_ vec: inout [Float]) {
        var sumSq: Float = 0
        vDSP_svesq(vec, 1, &sumSq, vDSP_Length(vec.count))
        let norm = sqrt(sumSq)
        guard norm > 1e-6 else { return }
        var inv = 1.0 / norm
        vDSP_vsmul(vec, 1, &inv, &vec, 1, vDSP_Length(vec.count))
    }
}
