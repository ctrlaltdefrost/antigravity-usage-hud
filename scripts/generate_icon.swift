import Cocoa
import CoreGraphics

func createReactorIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let center = CGPoint(x: size / 2.0, y: size / 2.0)
    let radius = size * 0.46

    // 1. App Icon Rounded Squircle Background (macOS style)
    let squircleRect = bounds.insetBy(dx: size * 0.04, dy: size * 0.04)
    let cornerRadius = size * 0.22
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Deep cosmic dark background gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.02, green: 0.04, blue: 0.08, alpha: 1.0),
        CGColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1.0)
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.6, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawRadialGradient(bgGradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.7, options: .drawsAfterEndLocation)
    }

    // Hexagonal / Grid subtle mesh pattern
    ctx.setStrokeColor(CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 0.04))
    ctx.setLineWidth(size * 0.003)
    let gridSpacing = size * 0.05
    var x: CGFloat = squircleRect.minX
    while x <= squircleRect.maxX {
        ctx.move(to: CGPoint(x: x, y: squircleRect.minY))
        ctx.addLine(to: CGPoint(x: x, y: squircleRect.maxY))
        x += gridSpacing
    }
    var y: CGFloat = squircleRect.minY
    while y <= squircleRect.maxY {
        ctx.move(to: CGPoint(x: squircleRect.minX, y: y))
        ctx.addLine(to: CGPoint(x: squircleRect.maxX, y: y))
        y += gridSpacing
    }
    ctx.strokePath()

    // 2. Outer Chassis Bezel Ring
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.22, blue: 0.35, alpha: 0.8))
    ctx.setLineWidth(size * 0.03)
    ctx.addArc(center: center, radius: radius * 0.95, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Outer glow ring
    ctx.setShadow(offset: .zero, blur: size * 0.05, color: CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 0.5))
    ctx.setStrokeColor(CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 0.6))
    ctx.setLineWidth(size * 0.012)
    ctx.addArc(center: center, radius: radius * 0.95, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState() // restore shadow

    // 3. Segmented Reactor Coils / Radial Notches (10 magnetic accelerator coils)
    let coilCount = 10
    for i in 0..<coilCount {
        let angle = (CGFloat(i) / CGFloat(coilCount)) * .pi * 2
        let innerR = radius * 0.68
        let outerR = radius * 0.92
        let p1 = CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR)
        let p2 = CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)

        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.75))
        ctx.setLineWidth(size * 0.02)
        ctx.setLineCap(.round)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()

        // Coil winding highlights
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.9)) // copper/gold magnetic coil
        ctx.setLineWidth(size * 0.01)
        let midR1 = radius * 0.76
        let midR2 = radius * 0.84
        let mp1 = CGPoint(x: center.x + cos(angle) * midR1, y: center.y + sin(angle) * midR1)
        let mp2 = CGPoint(x: center.x + cos(angle) * midR2, y: center.y + sin(angle) * midR2)
        ctx.move(to: mp1)
        ctx.addLine(to: mp2)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 4. Middle Arc Segment Ring with Orbital Dashes
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 0.4))
    ctx.setLineWidth(size * 0.015)
    let dashLengths: [CGFloat] = [size * 0.04, size * 0.02, size * 0.01, size * 0.02]
    ctx.setLineDash(phase: 0, lengths: dashLengths)
    ctx.addArc(center: center, radius: radius * 0.62, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Plasma Confinement Field Inner Glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.08, color: CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 0.9))
    ctx.setFillColor(CGColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.3))
    ctx.addArc(center: center, radius: radius * 0.52, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.restoreGState()

    // 6. Triangular Magnetic Focus Reticles (Arc Reactor aperture)
    let triangleCount = 3
    for i in 0..<triangleCount {
        let baseAngle = (CGFloat(i) / CGFloat(triangleCount)) * .pi * 2 - (.pi / 2.0)
        let rTip = radius * 0.28
        let rBase = radius * 0.52
        let tipP = CGPoint(x: center.x + cos(baseAngle) * rTip, y: center.y + sin(baseAngle) * rTip)
        let baseP1 = CGPoint(x: center.x + cos(baseAngle - 0.35) * rBase, y: center.y + sin(baseAngle - 0.35) * rBase)
        let baseP2 = CGPoint(x: center.x + cos(baseAngle + 0.35) * rBase, y: center.y + sin(baseAngle + 0.35) * rBase)

        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.22, alpha: 0.85))
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 0.8))
        ctx.setLineWidth(size * 0.008)
        ctx.beginPath()
        ctx.move(to: tipP)
        ctx.addLine(to: baseP1)
        ctx.addLine(to: baseP2)
        ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }

    // 7. Radiant Plasma Core (Blinding center with radial gradient)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.07, color: CGColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 1.0))
    let coreColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),      // Pure white nucleus
        CGColor(red: 0.5, green: 0.95, blue: 1.0, alpha: 0.95),   // Ice cyan
        CGColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.7),     // Laser cyan
        CGColor(red: 0.0, green: 0.3, blue: 0.9, alpha: 0.2),     // Cobalt falloff
        CGColor(red: 0.0, green: 0.1, blue: 0.3, alpha: 0.0)      // Transparent boundary
    ] as CFArray
    let coreLocations: [CGFloat] = [0.0, 0.2, 0.5, 0.8, 1.0]
    if let coreGrad = CGGradient(colorsSpace: colorSpace, colors: coreColors, locations: coreLocations) {
        ctx.drawRadialGradient(coreGrad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius * 0.35, options: .drawsAfterEndLocation)
    }
    ctx.restoreGState()

    // 8. Core Lens Flare Cross Glint
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    let glintLen = radius * 0.45
    let glintWidth = size * 0.008
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
    ctx.setLineWidth(glintWidth)
    // Horizontal flare
    ctx.move(to: CGPoint(x: center.x - glintLen, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x + glintLen, y: center.y))
    // Vertical flare
    ctx.move(to: CGPoint(x: center.x, y: center.y - glintLen))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + glintLen))
    ctx.strokePath()
    ctx.restoreGState()

    // Subtle edge highlight on squircle rim
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.4))
    ctx.setLineWidth(size * 0.01)
    ctx.strokePath()
    ctx.restoreGState()

    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, targetSize: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetSize,
        pixelsHigh: targetSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap rep")
    }

    rep.size = NSSize(width: targetSize, height: targetSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
               from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG data")
    }
    try? pngData.write(to: url)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tempIconsetDir = FileManager.default.temporaryDirectory.appendingPathComponent("AntigravityHUD.iconset")
try? FileManager.default.removeItem(at: tempIconsetDir)
try! FileManager.default.createDirectory(at: tempIconsetDir, withIntermediateDirectories: true)

let masterImage = createReactorIcon(size: 1024)

let iconSizes: [(String, Int)] = [
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

for (name, px) in iconSizes {
    let fileURL = tempIconsetDir.appendingPathComponent(name)
    savePNG(image: masterImage, targetSize: px, to: fileURL)
}

let outURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", tempIconsetDir.path, "-o", outURL.path]
try! process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(at: tempIconsetDir)

if process.terminationStatus == 0 {
    print("Successfully generated reactor icon at \(outURL.path)")
} else {
    print("iconutil failed with code \(process.terminationStatus)")
    exit(1)
}
