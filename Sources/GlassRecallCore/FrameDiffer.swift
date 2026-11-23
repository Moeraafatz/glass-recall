import CoreGraphics
import Foundation

public struct FrameSignature: Sendable, Equatable {
    public let lumaGrid: [UInt8]
    public let dHash: UInt64
    public let width: Int
    public let height: Int

    public init(lumaGrid: [UInt8], dHash: UInt64, width: Int, height: Int) {
        self.lumaGrid = lumaGrid
        self.dHash = dHash
        self.width = width
        self.height = height
    }
}

public struct FrameDiffResult: Sendable {
    public let shouldProcess: Bool
    public let changedCellRatio: Double
    public let meanAbsoluteDelta: Double
    public let hammingDistance: Int
    public let durationMs: Double
    public let signature: FrameSignature

    public init(
        shouldProcess: Bool,
        changedCellRatio: Double,
        meanAbsoluteDelta: Double,
        hammingDistance: Int,
        durationMs: Double,
        signature: FrameSignature
    ) {
        self.shouldProcess = shouldProcess
        self.changedCellRatio = changedCellRatio
        self.meanAbsoluteDelta = meanAbsoluteDelta
        self.hammingDistance = hammingDistance
        self.durationMs = durationMs
        self.signature = signature
    }
}

public final class FrameDiffer: @unchecked Sendable {
    public static let gridWidth = 64
    public static let gridHeight = 36
    private static let pixelDeltaCutoff: Int = 12

    private let lock = NSLock()
    private var previousSignature: FrameSignature?

    public init() {}

    public func reset() {
        lock.lock()
        previousSignature = nil
        lock.unlock()
    }

    public func evaluate(image: CGImage, threshold: Double = 0.025) -> FrameDiffResult {
        let start = CFAbsoluteTimeGetCurrent()
        let sig = Self.computeSignature(from: image)

        lock.lock()
        let prev = previousSignature
        lock.unlock()

        guard let prev, prev.lumaGrid.count == sig.lumaGrid.count else {
            lock.lock()
            previousSignature = sig
            lock.unlock()
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            return FrameDiffResult(
                shouldProcess: true,
                changedCellRatio: 1.0,
                meanAbsoluteDelta: 255.0,
                hammingDistance: 64,
                durationMs: elapsed,
                signature: sig
            )
        }

        let count = sig.lumaGrid.count
        var changedCells = 0
        var totalAbsDiff = 0

        for i in 0..<count {
            let diff = abs(Int(sig.lumaGrid[i]) - Int(prev.lumaGrid[i]))
            totalAbsDiff += diff
            if diff >= Self.pixelDeltaCutoff {
                changedCells += 1
            }
        }

        let changedRatio = Double(changedCells) / Double(max(count, 1))
        let mad = Double(totalAbsDiff) / Double(max(count, 1))
        let hamming = (sig.dHash ^ prev.dHash).nonzeroBitCount
        let shouldProcess = changedRatio >= threshold || hamming >= 6

        if shouldProcess {
            lock.lock()
            previousSignature = sig
            lock.unlock()
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        return FrameDiffResult(
            shouldProcess: shouldProcess,
            changedCellRatio: changedRatio,
            meanAbsoluteDelta: mad,
            hammingDistance: hamming,
            durationMs: elapsed,
            signature: sig
        )
    }

    public static func computeSignature(from image: CGImage) -> FrameSignature {
        let w = gridWidth
        let h = gridHeight
        var buffer = [UInt8](repeating: 0, count: w * h)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        buffer.withUnsafeMutableBytes { rawBuf in
            guard let baseAddress = rawBuf.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return
            }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        // Compute 64-bit dHash over an 9x8 subsample of the grayscale grid
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for row in 0..<8 {
            let y = (row * h) / 8
            for col in 0..<8 {
                let x1 = (col * w) / 9
                let x2 = ((col + 1) * w) / 9
                let left = buffer[y * w + x1]
                let right = buffer[y * w + x2]
                if left > right {
                    hash |= (1 << bit)
                }
                bit += 1
            }
        }

        return FrameSignature(lumaGrid: buffer, dHash: hash, width: w, height: h)
    }
}
