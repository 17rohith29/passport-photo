// Renders the two optional product-page assets: the header and the search-results card.
//
// These are not screenshots. Apple shows them above the screenshot strip and, for the search
// one, INSTEAD of the screenshots in search results, so they have to carry the whole pitch on
// their own at a size where only a few words survive.
//
// Sizes are the ones App Store Connect lists for each well. They are not interchangeable:
// the header is a wide banner, the search card is 3:2.
//
// usage: store-banner <raw-capture-dir> <output-dir>
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
// Straight from the app icon, same as store-shot.
let navyTop: CGColor = rgb(0x2E3866)
let navyBottom: CGColor = rgb(0x141936)
let amber: CGColor = rgb(0xF7BC4C)

enum Shape {
    /// Wide banner: text left, device right.
    case header
    /// 3:2 card: text above, device below.
    case search
}

struct Banner {
    var file: String
    var width: CGFloat
    var height: CGFloat
    var headline: String
    var subline: String
    var shape: Shape
}

let banners: [Banner] = [
    Banner(file: "header.png", width: 3840, height: 1646,
           // Explicit break: left to itself the line orphans "size", which reads as a mistake.
           headline: "Cut to the\nexact size",
           subline: "Passport and visa photos, measured on your iPhone. Nothing uploaded.",
           shape: .header),

    Banner(file: "search-results.png", width: 3840, height: 2560,
           headline: "Passport photos\nthat measure up",
           subline: "Free. No watermark. Nothing uploaded.",
           shape: .search),
]

let args: [String] = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: store-banner rawDir outDir\n", stderr); exit(2) }
let rawDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

func load(_ name: String) -> CGImage? {
    let url = rawDir.appendingPathComponent(name) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// The home screen with its empty lower half cropped away, same region store-shot uses.
let homeCrop = CGRect(x: 30, y: 250, width: 1260, height: 2000)

for banner in banners {
    let W: CGFloat = banner.width
    let H: CGFloat = banner.height

    guard let home = load("1-home.png"), let shot = home.cropping(to: homeCrop) else {
        fputs("missing or uncroppable 1-home.png\n", stderr); exit(1)
    }

    let space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    // noneSkipLast: the store rejects an asset carrying alpha. See store-shot.
    guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fputs("could not make context\n", stderr); exit(1)
    }

    let gradient: CGGradient = CGGradient(colorsSpace: space,
                                         colors: [navyTop, navyBottom] as CFArray,
                                         locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, colour: CGColor,
              rect: CGRect, align: NSTextAlignment, tracking: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineHeightMultiple = 1.06
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: colour)!,
            .paragraphStyle: para,
            .kern: tracking,
        ]
        let a = NSAttributedString(string: string, attributes: attrs)
        let setter = CTFramesetterCreateWithAttributedString(a)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                             CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
    }

    func measure(_ string: String, size: CGFloat, weight: NSFont.Weight,
                 tracking: CGFloat, width: CGFloat) -> CGSize {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.06
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .paragraphStyle: para,
            .kern: tracking,
        ]
        let a = NSAttributedString(string: string, attributes: attrs)
        let setter = CTFramesetterCreateWithAttributedString(a)
        let cap = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, cap, nil)
    }

    func card(_ image: CGImage, in rect: CGRect, radius: CGFloat) {
        let glow: CGGradient = CGGradient(colorsSpace: space,
                                          colors: [rgb(0x6E7CC4, 0.32), rgb(0x6E7CC4, 0)] as CFArray,
                                          locations: [0, 1])!
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: rect.width * 1.5, options: [])

        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                          transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: rgb(0, 0.5))
        ctx.addPath(path)
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    /// The icon's crop marks, framing the device. `topOnly` is for a device that runs off the
    /// bottom edge, where a bottom mark would hang in space below the canvas.
    func cropMarks(around rect: CGRect, arm: CGFloat, gap: CGFloat, thickness: CGFloat,
                   topOnly: Bool) {
        ctx.setFillColor(amber)
        let x0 = rect.minX - gap, x1 = rect.maxX + gap
        let y0 = rect.minY - gap, y1 = rect.maxY + gap
        // top-left
        ctx.fill(CGRect(x: x0 - thickness, y: y1 - arm, width: thickness, height: arm))
        ctx.fill(CGRect(x: x0 - thickness, y: y1, width: arm, height: thickness))
        if topOnly {
            // top-right
            ctx.fill(CGRect(x: x1, y: y1 - arm, width: thickness, height: arm))
            ctx.fill(CGRect(x: x1 - arm + thickness, y: y1, width: arm, height: thickness))
        } else {
            // bottom-right
            ctx.fill(CGRect(x: x1, y: y0, width: thickness, height: arm))
            ctx.fill(CGRect(x: x1 - arm + thickness, y: y0 - thickness,
                            width: arm, height: thickness))
        }
    }

    let shotAspect: CGFloat = CGFloat(shot.width) / CGFloat(shot.height)

    switch banner.shape {
    case .header:
        // Device sits right of centre; the text gets the wider left column.
        let deviceH: CGFloat = H * 0.80
        let deviceW: CGFloat = deviceH * shotAspect
        let deviceX: CGFloat = W * 0.66
        let deviceRect = CGRect(x: deviceX, y: (H - deviceH) / 2, width: deviceW, height: deviceH)
        card(shot, in: deviceRect, radius: 44)
        cropMarks(around: deviceRect, arm: 120, gap: 46, thickness: 12, topOnly: false)

        let colWidth: CGFloat = W * 0.50
        let left: CGFloat = W * 0.075
        let headSize: CGFloat = 230
        let headH = measure(banner.headline, size: headSize, weight: .heavy,
                            tracking: -6, width: colWidth).height
        let subSize: CGFloat = 80
        let subH = measure(banner.subline, size: subSize, weight: .medium,
                           tracking: 0, width: colWidth).height
        let ruleH: CGFloat = 12
        let block = headH + 54 + ruleH + 54 + subH
        let top = (H - block) / 2

        text(banner.headline, size: headSize, weight: .heavy, colour: rgb(0xFFFFFF),
             rect: CGRect(x: left, y: H - top - headH, width: colWidth, height: headH + 20),
             align: .left, tracking: -6)
        ctx.setFillColor(amber)
        ctx.fill(CGRect(x: left, y: H - top - headH - 54 - ruleH, width: 180, height: ruleH))
        text(banner.subline, size: subSize, weight: .medium, colour: rgb(0xC9D0EA),
             rect: CGRect(x: left, y: H - top - block, width: colWidth, height: subH + 20),
             align: .left, tracking: 0)

    case .search:
        let headSize: CGFloat = 206
        let colWidth: CGFloat = W * 0.80
        let left: CGFloat = (W - colWidth) / 2
        let headH = measure(banner.headline, size: headSize, weight: .heavy,
                            tracking: -5, width: colWidth).height
        let subSize: CGFloat = 78
        let subH = measure(banner.subline, size: subSize, weight: .medium,
                           tracking: 0, width: colWidth).height

        let top: CGFloat = H * 0.085
        text(banner.headline, size: headSize, weight: .heavy, colour: rgb(0xFFFFFF),
             rect: CGRect(x: left, y: H - top - headH, width: colWidth, height: headH + 20),
             align: .center, tracking: -5)
        let ruleY = top + headH + 52
        ctx.setFillColor(amber)
        ctx.fill(CGRect(x: W / 2 - 90, y: H - ruleY - 12, width: 180, height: 12))
        text(banner.subline, size: subSize, weight: .medium, colour: rgb(0xC9D0EA),
             rect: CGRect(x: left, y: H - ruleY - 60 - subH, width: colWidth, height: subH + 20),
             align: .center, tracking: 0)

        // The device runs off the bottom edge, so it reads as a phone in use.
        let contentTop = ruleY + 60 + subH + 150
        let deviceW: CGFloat = W * 0.30
        let deviceH: CGFloat = deviceW / shotAspect
        let deviceRect = CGRect(x: (W - deviceW) / 2, y: H - contentTop - deviceH,
                                width: deviceW, height: deviceH)
        card(shot, in: deviceRect, radius: 44)
        cropMarks(around: deviceRect, arm: 130, gap: 50, thickness: 13, topOnly: true)
    }

    guard let image = ctx.makeImage() else {
        fputs("could not render \(banner.file)\n", stderr); exit(1)
    }
    let out = outDir.appendingPathComponent(banner.file) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(out, UTType.png.identifier as CFString, 1, nil)
    else {
        fputs("could not open \(banner.file) for writing\n", stderr); exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("could not write \(banner.file)\n", stderr); exit(1)
    }
    print("wrote \(banner.file) \(Int(W))x\(Int(H))")
}
