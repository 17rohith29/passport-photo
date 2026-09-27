// Composites an App Store marketing screenshot: brand background, headline, subline, the raw
// simulator capture inset with the icon's crop-corner motif around it.
//
// usage: store-shot <input.png> <output.png> "Headline" "Subline"
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 1320.0, H = 2868.0

// From the app icon: deep navy, amber crop marks.
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let navyTop = rgb(0x2E3866), navyBottom = rgb(0x141936), amber = rgb(0xF7BC4C)

let args = CommandLine.arguments
guard args.count >= 5 else { fputs("usage: store-shot in out headline subline\n", stderr); exit(2) }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let headline = args[3], subline = args[4]

guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fputs("cannot read \(inURL.path)\n", stderr); exit(1)
}

let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background gradient.
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [navyTop, navyBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// Text is drawn with CoreText in native CG coordinates, so no flipping games.
func measure(_ text: String, size: CGFloat, weight: NSFont.Weight,
             tracking: CGFloat) -> CGSize {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 1.06
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .paragraphStyle: para, .kern: tracking,
    ])
    let setter = CTFramesetterCreateWithAttributedString(attributed)
    return CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: 0), nil,
        CGSize(width: W - 180, height: .greatestFiniteMagnitude), nil)
}

/// Largest size at or below `size` that keeps the headline within `maxLines`.
func fittedSize(_ text: String, from size: CGFloat, weight: NSFont.Weight,
                tracking: CGFloat, maxLines: Int) -> CGFloat {
    var candidate = size
    while candidate > 58 {
        let h = measure(text, size: candidate, weight: weight, tracking: tracking).height
        if h <= candidate * 1.14 * CGFloat(maxLines) + 6 { return candidate }
        candidate -= 4
    }
    return candidate
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, colour: CGColor,
          topY: CGFloat, height: CGFloat, tracking: CGFloat = -1.5) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 1.06
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: colour)!,
        .paragraphStyle: para, .kern: tracking,
    ])
    let setter = CTFramesetterCreateWithAttributedString(attributed)
    let bounds = CGRect(x: 90, y: H - topY - height, width: W - 180, height: height)
    let path = CGPath(rect: bounds, transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
    CTFrameDraw(frame, ctx)
    let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: 0), nil,
        CGSize(width: W - 180, height: .greatestFiniteMagnitude), nil)
    return fitted.height
}

// Headline block, then an amber rule, then the subline.
let headlineTop = 138.0
let headlineSize = fittedSize(headline, from: 108, weight: .heavy, tracking: -2, maxLines: 2)
let headlineHeight = draw(headline, size: headlineSize, weight: .heavy, colour: rgb(0xFFFFFF),
                          topY: headlineTop, height: 420, tracking: -2)

let ruleY = headlineTop + headlineHeight + 44
ctx.setFillColor(amber)
ctx.fill(CGRect(x: W / 2 - 54, y: H - ruleY - 8, width: 108, height: 8))

if !subline.isEmpty {
    _ = draw(subline, size: 46, weight: .medium, colour: rgb(0xC9D0EA), topY: ruleY + 46,
             height: 200, tracking: 0)
}

// The capture, inset with rounded corners and a soft shadow.
let shotWidth = 980.0
let scale = shotWidth / CGFloat(shot.width)
let shotHeight = CGFloat(shot.height) * scale
let shotX = (W - shotWidth) / 2
let shotY = 118.0                      // from the bottom
let rect = CGRect(x: shotX, y: shotY, width: shotWidth, height: shotHeight)
let rounded = CGPath(roundedRect: rect, cornerWidth: 54, cornerHeight: 54, transform: nil)

let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [rgb(0x6E7CC4, 0.30), rgb(0x6E7CC4, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: shotY + shotHeight * 0.62),
                       startRadius: 0,
                       endCenter: CGPoint(x: W / 2, y: shotY + shotHeight * 0.62),
                       endRadius: W * 0.72, options: [])

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 54, color: rgb(0x000000, 0.45))
ctx.addPath(rounded)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rounded)
ctx.clip()
ctx.draw(shot, in: rect)
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rounded)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// The icon's crop marks, framing the phone the way they frame the portrait.
func cropMark(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
    let arm = 86.0, thick = 11.0
    ctx.setFillColor(amber)
    ctx.fill(CGRect(x: x, y: y, width: arm * dx, height: thick * (dy > 0 ? 1 : 1)))
    ctx.fill(CGRect(x: x, y: y, width: thick, height: arm * dy))
}
let inset = 52.0
cropMark(x: rect.minX - inset, y: rect.maxY + inset, dx: 1, dy: -1)
cropMark(x: rect.maxX + inset - 86, y: rect.minY - inset, dx: 1, dy: 1)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)
else { fputs("render failed\n", stderr); exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.lastPathComponent) \(image.width)x\(image.height)")
