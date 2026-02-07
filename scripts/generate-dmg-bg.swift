#!/usr/bin/env swift

import AppKit
import Foundation

let width: CGFloat = 600
let height: CGFloat = 400

func drawBackground(ctx: CGContext, scale: CGFloat) {
    ctx.scaleBy(x: scale, y: scale)

    // Background gradient (clean white-to-light-gray)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0),
        CGColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0)
    ] as CFArray
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // ── Title at top ──
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .bold),
        .foregroundColor: NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0)
    ]
    let title = "MemoExport" as NSString
    let titleSize = title.size(withAttributes: titleAttrs)
    title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 52), withAttributes: titleAttrs)

    // ── Subtitle ──
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(red: 0.45, green: 0.45, blue: 0.5, alpha: 1.0)
    ]
    let sub = "Apple メモ エクスポートツール" as NSString
    let subSize = sub.size(withAttributes: subAttrs)
    sub.draw(at: NSPoint(x: (width - subSize.width) / 2, y: height - 75), withAttributes: subAttrs)

    // ── Large curved arrow from app icon to Applications ──
    let arrowY: CGFloat = height * 0.48
    let arrowStartX: CGFloat = 210
    let arrowEndX: CGFloat = 395

    // Dashed arrow shaft with curve
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 0.7))
    ctx.setLineWidth(3.5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [8, 5])

    let path = CGMutablePath()
    path.move(to: CGPoint(x: arrowStartX, y: arrowY))
    path.addCurve(
        to: CGPoint(x: arrowEndX, y: arrowY),
        control1: CGPoint(x: arrowStartX + 50, y: arrowY + 30),
        control2: CGPoint(x: arrowEndX - 50, y: arrowY + 30)
    )
    ctx.addPath(path)
    ctx.strokePath()

    // Arrow head (solid)
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 0.7))
    let headSize: CGFloat = 14
    let headPath = CGMutablePath()
    headPath.move(to: CGPoint(x: arrowEndX + 2, y: arrowY))
    headPath.addLine(to: CGPoint(x: arrowEndX - headSize, y: arrowY + headSize * 0.7))
    headPath.addLine(to: CGPoint(x: arrowEndX - headSize, y: arrowY - headSize * 0.7))
    headPath.closeSubpath()
    ctx.addPath(headPath)
    ctx.fillPath()

    // ── Instruction label ──
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
        .foregroundColor: NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 0.9)
    ]
    let label = "ドラッグしてインストール" as NSString
    let labelSize = label.size(withAttributes: labelAttrs)
    label.draw(at: NSPoint(x: (width - labelSize.width) / 2, y: arrowY - 32), withAttributes: labelAttrs)

    // ── Left label (app icon) ──
    let iconLabelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.8)
    ]
    let leftLabel = "MemoExport.app" as NSString
    let leftSize = leftLabel.size(withAttributes: iconLabelAttrs)
    leftLabel.draw(at: NSPoint(x: 155 - leftSize.width / 2, y: arrowY - 80), withAttributes: iconLabelAttrs)

    // ── Right label (Applications) ──
    let rightLabel = "Applications" as NSString
    let rightSize = rightLabel.size(withAttributes: iconLabelAttrs)
    rightLabel.draw(at: NSPoint(x: 445 - rightSize.width / 2, y: arrowY - 80), withAttributes: iconLabelAttrs)

    // ── Bottom help text ──
    let helpAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 0.8)
    ]
    let help = "初回起動時に「メモ」アプリへのアクセス許可が必要です" as NSString
    let helpSize = help.size(withAttributes: helpAttrs)
    help.draw(at: NSPoint(x: (width - helpSize.width) / 2, y: 30), withAttributes: helpAttrs)
}

// 1x version
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
drawBackground(ctx: NSGraphicsContext.current!.cgContext, scale: 1.0)
image.unlockFocus()

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let outputPath = projectDir.appendingPathComponent("Resources/dmg-background.png").path
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("ERROR: Failed to generate background image")
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("DMG background created: \(outputPath) (\(Int(width))x\(Int(height)))")

// 2x version
let image2x = NSImage(size: NSSize(width: width * 2, height: height * 2))
image2x.lockFocus()
drawBackground(ctx: NSGraphicsContext.current!.cgContext, scale: 2.0)
image2x.unlockFocus()

let outputPath2x = projectDir.appendingPathComponent("Resources/dmg-background@2x.png").path
guard let tiffData2x = image2x.tiffRepresentation,
      let bitmap2x = NSBitmapImageRep(data: tiffData2x),
      let pngData2x = bitmap2x.representation(using: .png, properties: [:]) else {
    print("ERROR: Failed to generate @2x background image")
    exit(1)
}
try pngData2x.write(to: URL(fileURLWithPath: outputPath2x))
print("DMG background @2x created: \(outputPath2x) (\(Int(width * 2))x\(Int(height * 2)))")
