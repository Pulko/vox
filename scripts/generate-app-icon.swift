#!/usr/bin/env swift
import AppKit
import Foundation

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    NSColor.clear.setFill()
    rect.fill()

    let inset: CGFloat = 72
    let box = rect.insetBy(dx: inset, dy: inset)
    let radius = box.width * 0.223
    let background = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
    background.fill()

    let circleSide = box.width * 0.62
    let circle = NSRect(
        x: box.midX - circleSide / 2,
        y: box.midY - circleSide / 2,
        width: circleSide,
        height: circleSide
    )
    NSColor.white.setFill()
    NSBezierPath(ovalIn: circle).fill()

    NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
    let scale = circleSide / 18
    let origin = circle.origin
    let barWidth: CGFloat = 1.45 * scale
    let bars: [(CGFloat, CGFloat)] = [
        (5.7, 4.4),
        (7.6, 7.8),
        (9.5, 5.6),
        (11.4, 6.8),
    ]
    for (x, height) in bars {
        let barHeight = height * scale
        let bar = NSBezierPath(
            roundedRect: NSRect(
                x: origin.x + x * scale,
                y: origin.y + (9 - height / 2) * scale,
                width: barWidth,
                height: barHeight
            ),
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )
        bar.fill()
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to encode icon\n", stderr)
    exit(1)
}

let dest = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
try png.write(to: URL(fileURLWithPath: dest))
