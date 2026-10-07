// Draws the app icon: a white silhouette of a woman running, on black.
//
// Usage: swift Tools/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// The figure is built from thick round-capped strokes on a 1024-point canvas, with y increasing downward.

import AppKit

let size = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

// Opaque RGB context: App Store icons must not have an alpha channel.
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Flip so y grows downward, matching the coordinates below.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let white = CGColor(gray: 1, alpha: 1)
context.setStrokeColor(white)
context.setFillColor(white)
context.setLineCap(.round)
context.setLineJoin(.round)

func stroke(_ points: [CGPoint], width: CGFloat) {
    context.setLineWidth(width)
    context.addLines(between: points)
    context.strokePath()
}

let neck = CGPoint(x: 598, y: 352)
let hip = CGPoint(x: 505, y: 568)
let shoulder = CGPoint(x: 580, y: 392)

// Head.
context.fillEllipse(in: CGRect(x: 588, y: 172, width: 128, height: 128))

// Ponytail: a tapered swoosh streaming from the back of the head.
context.move(to: CGPoint(x: 610, y: 196))
context.addCurve(to: CGPoint(x: 448, y: 300), control1: CGPoint(x: 545, y: 182), control2: CGPoint(x: 485, y: 228))
context.addCurve(to: CGPoint(x: 602, y: 262), control1: CGPoint(x: 505, y: 288), control2: CGPoint(x: 560, y: 282))
context.closePath()
context.fillPath()

// Torso, leaning into the run.
stroke([neck, hip], width: 108)

// Back arm: elbow behind, forearm swinging up.
stroke([shoulder, CGPoint(x: 462, y: 482), CGPoint(x: 400, y: 405)], width: 60)

// Front arm: elbow forward and low, hand rising.
stroke([shoulder, CGPoint(x: 688, y: 475), CGPoint(x: 782, y: 408)], width: 60)

// Front leg: knee driving forward, shin reaching down.
stroke([hip, CGPoint(x: 685, y: 655), CGPoint(x: 645, y: 840)], width: 80)

// Back leg: pushing off, foot kicked up behind.
stroke([hip, CGPoint(x: 440, y: 742), CGPoint(x: 275, y: 795)], width: 80)

let image = context.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
