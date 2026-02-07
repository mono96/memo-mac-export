#!/usr/bin/env swift

import AppKit
import Foundation

// Generate app icon: a memo/note icon with an export arrow
func generateIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded rectangle with gradient
    let bgRect = CGRect(x: size * 0.05, y: size * 0.05, width: size * 0.9, height: size * 0.9)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil)

    // Gradient background (warm yellow to orange)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1.0),
        CGColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1.0)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])
    ctx.restoreGState()

    // Shadow for depth
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.001))
    ctx.fillPath()
    ctx.restoreGState()

    // Note paper icon (white rectangle with folded corner)
    let paperX = size * 0.22
    let paperY = size * 0.2
    let paperW = size * 0.42
    let paperH = size * 0.55
    let foldSize = size * 0.1

    let paperPath = CGMutablePath()
    paperPath.move(to: CGPoint(x: paperX, y: paperY))
    paperPath.addLine(to: CGPoint(x: paperX + paperW, y: paperY))
    paperPath.addLine(to: CGPoint(x: paperX + paperW, y: paperY + paperH - foldSize))
    paperPath.addLine(to: CGPoint(x: paperX + paperW - foldSize, y: paperY + paperH))
    paperPath.addLine(to: CGPoint(x: paperX, y: paperY + paperH))
    paperPath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: size * 0.01, height: -size * 0.015), blur: size * 0.03, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(paperPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Folded corner
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: paperX + paperW - foldSize, y: paperY + paperH))
    foldPath.addLine(to: CGPoint(x: paperX + paperW - foldSize, y: paperY + paperH - foldSize))
    foldPath.addLine(to: CGPoint(x: paperX + paperW, y: paperY + paperH - foldSize))
    foldPath.closeSubpath()

    ctx.setFillColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0))
    ctx.addPath(foldPath)
    ctx.fillPath()

    // Text lines on paper
    let lineColor = CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.8)
    ctx.setStrokeColor(lineColor)
    ctx.setLineWidth(size * 0.015)

    let lineStartX = paperX + size * 0.04
    let lineEndX = paperX + paperW - size * 0.05
    for i in 0..<4 {
        let lineY = paperY + size * 0.08 + CGFloat(i) * size * 0.09
        let endX = (i == 3) ? lineStartX + (lineEndX - lineStartX) * 0.6 : lineEndX
        ctx.move(to: CGPoint(x: lineStartX, y: lineY))
        ctx.addLine(to: CGPoint(x: endX, y: lineY))
        ctx.strokePath()
    }

    // Export arrow (right side, pointing out)
    let arrowCenterX = size * 0.72
    let arrowCenterY = size * 0.42
    let arrowLen = size * 0.18

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(size * 0.04)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Arrow shaft
    ctx.move(to: CGPoint(x: arrowCenterX - arrowLen * 0.4, y: arrowCenterY))
    ctx.addLine(to: CGPoint(x: arrowCenterX + arrowLen * 0.5, y: arrowCenterY))
    ctx.strokePath()

    // Arrow head
    let headSize = arrowLen * 0.35
    ctx.move(to: CGPoint(x: arrowCenterX + arrowLen * 0.5 - headSize, y: arrowCenterY + headSize))
    ctx.addLine(to: CGPoint(x: arrowCenterX + arrowLen * 0.5, y: arrowCenterY))
    ctx.addLine(to: CGPoint(x: arrowCenterX + arrowLen * 0.5 - headSize, y: arrowCenterY - headSize))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

// Generate iconset
let iconsetPath = "/Users/nobuhito/build/memo_mac_export/build/MemoExport.iconset"
let fm = FileManager.default

try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
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

for (name, size) in sizes {
    let image = generateIcon(size: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let filePath = "\(iconsetPath)/\(name).png"
    try pngData.write(to: URL(fileURLWithPath: filePath))
    print("Generated: \(name).png (\(Int(size))x\(Int(size)))")
}

print("Iconset created at: \(iconsetPath)")
