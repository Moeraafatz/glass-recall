import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconGenerator {
    static func generateIconSet(iconsetURL: URL, docsIconURL: URL) throws {
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsIconURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (name, px) in sizes {
            let img = renderIcon(size: px)
            try writePNG(img, to: iconsetURL.appendingPathComponent(name))
        }

        let docsImg = renderIcon(size: 256)
        try writePNG(docsImg, to: docsIconURL)
    }

    static func renderIcon(size: Int) -> CGImage {
        let s = CGFloat(size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // macOS rounded squircle inset
        let inset = s * 0.08
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = rect.width * 0.225
        let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Base obsidian gradient
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        let bgColors = [
            CGColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 1.0),
            CGColor(red: 0.04, green: 0.055, blue: 0.085, alpha: 1.0),
            CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1.0)
        ] as CFArray
        let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.52, 1.0])!
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )

        // Top-left cyan glow
        let cyanGlow = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 0.34),
                CGColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            cyanGlow,
            startCenter: CGPoint(x: s * 0.34, y: s * 0.68),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.34, y: s * 0.68),
            endRadius: s * 0.48,
            options: []
        )

        // Bottom-right emerald glow
        let emeraldGlow = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.28),
                CGColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(
            emeraldGlow,
            startCenter: CGPoint(x: s * 0.68, y: s * 0.32),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.68, y: s * 0.32),
            endRadius: s * 0.44,
            options: []
        )

        // Subtle glass top sheen
        let sheenRect = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.5)
        let sheenGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.14),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(
            sheenGrad,
            start: CGPoint(x: sheenRect.midX, y: sheenRect.maxY),
            end: CGPoint(x: sheenRect.midX, y: sheenRect.minY),
            options: []
        )

        let center = CGPoint(x: s * 0.5, y: s * 0.5)

        // Outer glass memory ring
        ctx.setLineWidth(max(1.5, s * 0.028))
        ctx.setStrokeColor(CGColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 0.85))
        ctx.addArc(center: center, radius: s * 0.275, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Inner emerald recall arc (open sweep indicating diff-gated temporal recall)
        ctx.setLineWidth(max(1.5, s * 0.036))
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.95))
        ctx.addArc(center: center, radius: s * 0.185, startAngle: .pi * 0.22, endAngle: .pi * 1.65, clockwise: false)
        ctx.strokePath()

        // Optical lens core
        let coreGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.86, green: 0.97, blue: 1.0, alpha: 1.0),
                CGColor(red: 0.39, green: 0.82, blue: 1.0, alpha: 0.92),
                CGColor(red: 0.14, green: 0.45, blue: 0.72, alpha: 0.2)
            ] as CFArray,
            locations: [0.0, 0.5, 1.0]
        )!
        ctx.drawRadialGradient(
            coreGrad,
            startCenter: CGPoint(x: center.x - s * 0.02, y: center.y + s * 0.02),
            startRadius: 0,
            endCenter: center,
            endRadius: s * 0.105,
            options: []
        )

        // Crisp reticle ticks around outer ring
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.45))
        ctx.setLineWidth(max(1.0, s * 0.014))
        for i in 0..<4 {
            let angle = CGFloat(i) * (.pi / 2.0)
            let p1 = CGPoint(x: center.x + cos(angle) * s * 0.31, y: center.y + sin(angle) * s * 0.31)
            let p2 = CGPoint(x: center.x + cos(angle) * s * 0.35, y: center.y + sin(angle) * s * 0.35)
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
        }

        ctx.restoreGState()

        // Crisp 1px glass squircle border
        ctx.addPath(squircle)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24))
        ctx.setLineWidth(max(1.0, s * 0.012))
        ctx.strokePath()

        return ctx.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "GlassRecallTools.PNG", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination at \(url.path)"])
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "GlassRecallTools.PNG", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG at \(url.path)"])
        }
    }
}
