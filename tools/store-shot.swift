// Renders the App Store screenshot set.
//
// The set is a narrative, not five pictures of the app: the photo you already have, measured,
// honest about its limits, printed, and free. Slides that make a point about one part of a
// screen show that part enlarged, because a whole iPhone screen is unreadable at the size these
// are actually browsed at.
//
// usage: store-shot <raw-capture-dir> <output-dir>
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 1320.0, H = 2868.0

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
// Straight from the app icon.
let navyTop = rgb(0x2E3866), navyBottom = rgb(0x141936)
let amber = rgb(0xF7BC4C), ink = rgb(0x141936)

struct Chip {
    var text: String
    /// Vertical position as a fraction of the canvas, measured from the top.
    var atY: CGFloat
}

enum Presentation {
    /// The whole screen, running off the bottom edge so it reads as a device in use.
    case device
    /// One region of a screen, enlarged. Used when the point is a detail.
    case detail(CGRect)
}

struct Slide {
    var file: String
    var source: String
    var headline: String
    var subline: String
    var presentation: Presentation
    var chips: [Chip] = []
}

// The story, in order. The first two are what most people ever see.
let slides: [Slide] = [
    Slide(file: "01-your-photo.png", source: "1-home.png",
          headline: "The photo you already have",
          subline: "Cut to the exact size your document wants",
          presentation: .device),

    Slide(file: "02-measured.png", source: "3-requirements.png",
          headline: "Measured, not guessed",
          subline: "Head height, eye line, background, file size",
          presentation: .detail(CGRect(x: 50, y: 420, width: 1220, height: 1300))),

    Slide(file: "03-honest.png", source: "3-requirements.png",
          headline: "And honest about the rest",
          subline: "A green tick is never a promise",
          presentation: .detail(CGRect(x: 50, y: 1780, width: 1220, height: 965))),

    Slide(file: "04-print.png", source: "4-saved-sheet.png",
          headline: "Then exactly how to print it",
          subline: "Paper, copies, and where to submit them",
          presentation: .detail(CGRect(x: 45, y: 965, width: 1230, height: 1370))),

    Slide(file: "05-countries.png", source: "2-picker.png",
          headline: "Several countries, one tap",
          subline: "Free. No account. Nothing uploaded.",
          presentation: .device),
]

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: store-shot rawDir outDir\n", stderr); exit(2) }
let rawDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])

func load(_ name: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(rawDir.appendingPathComponent(name) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

func measure(_ text: String, size: CGFloat, weight: NSFont.Weight,
             tracking: CGFloat, width: CGFloat) -> CGSize {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 1.05
    let a = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .paragraphStyle: para, .kern: tracking,
    ])
    let setter = CTFramesetterCreateWithAttributedString(a)
    return CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: 0), nil,
        CGSize(width: width, height: .greatestFiniteMagnitude), nil)
}

for slide in slides {
    guard let shot = load(slide.source) else {
        fputs("missing \(slide.source)\n", stderr); exit(1)
    }
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    ctx.drawLinearGradient(
        CGGradient(colorsSpace: space, colors: [navyTop, navyBottom] as CFArray,
                   locations: [0, 1])!,
        start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, colour: CGColor,
              topY: CGFloat, tracking: CGFloat, width: CGFloat = W - 170) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineHeightMultiple = 1.05
        let a = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: colour)!,
            .paragraphStyle: para, .kern: tracking,
        ])
        let setter = CTFramesetterCreateWithAttributedString(a)
        let box = CGRect(x: (W - width) / 2, y: H - topY - 500, width: width, height: 500)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                             CGPath(rect: box, transform: nil), nil), ctx)
    }

    // Headline shrinks rather than wrapping into a third line.
    var headSize = 108.0
    while headSize > 62,
          measure(slide.headline, size: headSize, weight: .heavy, tracking: -2,
                  width: W - 170).height > headSize * 1.16 * 2 + 6 {
        headSize -= 4
    }
    let headHeight = measure(slide.headline, size: headSize, weight: .heavy,
                             tracking: -2, width: W - 170).height
    text(slide.headline, size: headSize, weight: .heavy, colour: rgb(0xFFFFFF),
         topY: 140, tracking: -2)

    let ruleY = 140 + headHeight + 42
    ctx.setFillColor(amber)
    ctx.fill(CGRect(x: W / 2 - 54, y: H - ruleY - 8, width: 108, height: 8))
    text(slide.subline, size: 46, weight: .medium, colour: rgb(0xC9D0EA),
         topY: ruleY + 44, tracking: 0)

    let contentTop = ruleY + 44 + measure(slide.subline, size: 46, weight: .medium,
                                          tracking: 0, width: W - 170).height + 92

    func card(_ image: CGImage, in rect: CGRect, radius: CGFloat, glow: Bool) {
        if glow {
            ctx.drawRadialGradient(
                CGGradient(colorsSpace: space,
                           colors: [rgb(0x6E7CC4, 0.34), rgb(0x6E7CC4, 0)] as CFArray,
                           locations: [0, 1])!,
                startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: W * 0.7, options: [])
        }
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                          transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 56, color: rgb(0, 0.5))
        ctx.addPath(path); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path); ctx.clip(); ctx.draw(image, in: rect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(3); ctx.strokePath()
        ctx.restoreGState()
    }

    var deviceRect = CGRect.zero
    switch slide.presentation {
    case .device:
        // Runs off the bottom edge: a device in use, not a rectangle floating in space.
        let width = 1120.0
        let scale = width / CGFloat(shot.width)
        let height = CGFloat(shot.height) * scale
        let topY = contentTop + 26
        let rect = CGRect(x: (W - width) / 2, y: H - topY - height,
                          width: width, height: height)
        deviceRect = rect
        card(shot, in: rect, radius: 52, glow: true)

    case let .detail(crop):
        // One region, enlarged, so the point is legible at browsing size.
        guard let cut = shot.cropping(to: crop) else { exit(1) }
        let width = 1140.0
        let height = width * CGFloat(cut.height) / CGFloat(cut.width)
        let regionTop = contentTop              // measured from the top of the canvas
        let regionBottom = H - 150
        let topY = regionTop + max(0, (regionBottom - regionTop - height) * 0.34)
        let rect = CGRect(x: (W - width) / 2, y: H - topY - height,
                          width: width, height: height)
        deviceRect = rect
        card(cut, in: rect, radius: 38, glow: true)
    }

    // The icon's crop marks, framing the content the way they frame the portrait.
    func mark(x: CGFloat, y: CGFloat, flip: Bool) {
        let arm = 80.0, thick = 10.0
        ctx.setFillColor(amber)
        ctx.fill(CGRect(x: flip ? x - arm + thick : x, y: y, width: arm, height: thick))
        ctx.fill(CGRect(x: flip ? x : x, y: flip ? y : y - arm + thick,
                        width: thick, height: arm))
    }
    mark(x: deviceRect.minX - 46, y: deviceRect.maxY + 46, flip: false)
    if deviceRect.minY > 120 {
        mark(x: deviceRect.maxX + 46, y: deviceRect.minY - 46, flip: true)
    }

    for chip in slide.chips {
        let size = 40.0
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let a = NSAttributedString(string: chip.text, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: ink)!, .kern: 0,
        ])
        let line = CTLineCreateWithAttributedString(a)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let padX = 40.0, padY = 26.0
        let w = bounds.width + padX * 2, h = bounds.height + padY * 2
        let rect = CGRect(x: (W - w) / 2, y: H - chip.atY * H - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0, 0.35))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2,
                           transform: nil))
        ctx.setFillColor(amber); ctx.fillPath()
        ctx.restoreGState()
        ctx.textPosition = CGPoint(x: rect.minX + padX - bounds.minX,
                                   y: rect.minY + padY - bounds.minY)
        CTLineDraw(line, ctx)
    }

    guard let image = ctx.makeImage() else { exit(1) }
    let url = outDir.appendingPathComponent(slide.file)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(slide.file)")
}
