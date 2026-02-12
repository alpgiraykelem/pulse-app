import AppKit

func generateIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let s = CGFloat(size)
    let ctx = NSGraphicsContext.current!.cgContext

    // === Background: Rounded rect with gradient ===
    let inset = s * 0.04
    let cornerRadius = s * 0.22
    let bgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.24, green: 0.31, blue: 0.96, alpha: 1.0),  // #3D4FF5
        CGColor(red: 0.55, green: 0.22, blue: 0.88, alpha: 1.0),  // #8C38E0
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // Subtle inner shadow/highlight at top
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let highlightColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.2),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ]
    let highlight = CGGradient(colorsSpace: colorSpace, colors: highlightColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: s * 0.5, y: s * 0.96), end: CGPoint(x: s * 0.5, y: s * 0.55), options: [])
    ctx.restoreGState()

    // === Clock face ===
    let centerX = s * 0.5
    let centerY = s * 0.54
    let clockRadius = s * 0.27

    // White clock circle with subtle shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.04, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addEllipse(in: CGRect(x: centerX - clockRadius, y: centerY - clockRadius, width: clockRadius * 2, height: clockRadius * 2))
    ctx.fillPath()
    ctx.restoreGState()

    // Clock tick marks (12 marks)
    for i in 0..<12 {
        let angle = CGFloat(i) * (.pi / 6) - .pi / 2
        let outerR = clockRadius * 0.88
        let innerR = (i % 3 == 0) ? clockRadius * 0.7 : clockRadius * 0.78
        let lineWidth = (i % 3 == 0) ? s * 0.02 : s * 0.01

        let x1 = centerX + cos(angle) * innerR
        let y1 = centerY + sin(angle) * innerR
        let x2 = centerX + cos(angle) * outerR
        let y2 = centerY + sin(angle) * outerR

        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.35, alpha: 0.6))
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
    }

    // Hour hand (pointing ~2 o'clock)
    let hourAngle: CGFloat = .pi / 6 * 2 - .pi / 2  // 2 o'clock
    ctx.setStrokeColor(CGColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1.0))
    ctx.setLineWidth(s * 0.028)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: centerX, y: centerY))
    ctx.addLine(to: CGPoint(x: centerX + cos(hourAngle) * clockRadius * 0.45, y: centerY + sin(hourAngle) * clockRadius * 0.45))
    ctx.strokePath()

    // Minute hand (pointing ~10)
    let minuteAngle: CGFloat = .pi / 6 * 10 - .pi / 2  // 10 o'clock position
    ctx.setLineWidth(s * 0.018)
    ctx.move(to: CGPoint(x: centerX, y: centerY))
    ctx.addLine(to: CGPoint(x: centerX + cos(minuteAngle) * clockRadius * 0.65, y: centerY + sin(minuteAngle) * clockRadius * 0.65))
    ctx.strokePath()

    // Center dot (red recording indicator)
    let dotR = s * 0.028
    ctx.setFillColor(CGColor(red: 0.95, green: 0.22, blue: 0.22, alpha: 1.0))
    ctx.addEllipse(in: CGRect(x: centerX - dotR, y: centerY - dotR, width: dotR * 2, height: dotR * 2))
    ctx.fillPath()

    // === Stopwatch button at top ===
    let btnWidth = s * 0.05
    let btnHeight = s * 0.07
    let btnX = centerX - btnWidth / 2
    let btnY = centerY + clockRadius - s * 0.01
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    let btnPath = CGPath(roundedRect: CGRect(x: btnX, y: btnY, width: btnWidth, height: btnHeight), cornerWidth: btnWidth * 0.3, cornerHeight: btnWidth * 0.3, transform: nil)
    ctx.addPath(btnPath)
    ctx.fillPath()

    // === Activity bars at bottom ===
    let barBaseY = s * 0.12
    let barHeight = s * 0.05
    let barGap = s * 0.025
    let barX = s * 0.22

    struct BarInfo {
        let widthFraction: CGFloat
        let r: CGFloat, g: CGFloat, b: CGFloat
    }

    let bars: [BarInfo] = [
        BarInfo(widthFraction: 0.56, r: 0.2, g: 0.82, b: 0.55),   // green
        BarInfo(widthFraction: 0.40, r: 0.98, g: 0.72, b: 0.15),   // amber
        BarInfo(widthFraction: 0.28, r: 0.95, g: 0.35, b: 0.35),   // red
    ]

    for (i, bar) in bars.enumerated() {
        let y = barBaseY + CGFloat(i) * (barHeight + barGap)
        let w = s * bar.widthFraction
        let barRect = CGRect(x: barX, y: y, width: w, height: barHeight)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil)
        ctx.setFillColor(CGColor(red: bar.r, green: bar.g, blue: bar.b, alpha: 0.9))
        ctx.addPath(barPath)
        ctx.fillPath()
    }

    image.unlockFocus()
    return image
}

// --- Generate iconset ---
let iconsetPath = "/tmp/ActivityTracker.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let img = generateIcon(size: entry.size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed: \(entry.name)")
        continue
    }
    try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(entry.name).png"))
    print("OK \(entry.name).png")
}
print("Done. Run: iconutil -c icns \(iconsetPath)")
