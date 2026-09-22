import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// icon <out.png> <size>
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "icon.png")
let S = CGFloat(args.count > 2 ? Int(args[2]) ?? 1024 : 1024)

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, 1])!
}

// Deep indigo ground: serious, document-ish, and distinct from the white card on top.
let top = rgb(46, 60, 122), bottom = rgb(24, 30, 66)
if let grad = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
}

// The passport photo itself: a 35x45 card, the exact aspect the app produces.
let cardH = S * 0.62
let cardW = cardH * 35.0 / 45.0
let cardRect = CGRect(x: (S - cardW) / 2, y: (S - cardH) / 2 + S * 0.012, width: cardW, height: cardH)
let card = CGPath(roundedRect: cardRect, cornerWidth: S * 0.028, cornerHeight: S * 0.028, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.05,
              color: CGColor(colorSpace: space, components: [0, 0, 0, 0.45])!)
ctx.addPath(card)
ctx.setFillColor(rgb(252, 252, 252))
ctx.fillPath()
ctx.restoreGState()

// Head and shoulders, sized the way the app frames them: head ~36mm of a 45mm photo.
ctx.saveGState()
ctx.addPath(card)
ctx.clip()

let figure = rgb(38, 48, 96)
ctx.setFillColor(figure)

// The app frames the head at ~80% of the photo height for India, so the icon shows the same
// thing rather than a generic avatar: real top margin, a visible neck, shoulders cut by the edge.
let headH = cardH * 0.46
let headW = headH * 0.76
let headCx = cardRect.midX
let headTopY = cardRect.maxY - cardH * 0.10          // top margin above the crown
let headBottomY = headTopY - headH

ctx.setFillColor(figure)
ctx.addEllipse(in: CGRect(x: headCx - headW / 2, y: headBottomY, width: headW, height: headH))
ctx.fillPath()

// Neck: short and narrower than the jaw, so the head reads as a head.
let neckW = headW * 0.42
let neckTop = headBottomY + headH * 0.08
let neckBottom = headBottomY - cardH * 0.055
ctx.addRect(CGRect(x: headCx - neckW / 2, y: neckBottom, width: neckW, height: neckTop - neckBottom))
ctx.fillPath()

// Shoulders: a shallow arc running off both edges, meeting the bottom of the card.
let shoulderW = cardW * 1.30
let shoulderTop = neckBottom + cardH * 0.035
let shoulders = CGMutablePath()
shoulders.move(to: CGPoint(x: headCx - shoulderW / 2, y: cardRect.minY))
shoulders.addCurve(to: CGPoint(x: headCx, y: shoulderTop),
                   control1: CGPoint(x: headCx - shoulderW / 2, y: shoulderTop - cardH * 0.02),
                   control2: CGPoint(x: headCx - shoulderW * 0.19, y: shoulderTop))
shoulders.addCurve(to: CGPoint(x: headCx + shoulderW / 2, y: cardRect.minY),
                   control1: CGPoint(x: headCx + shoulderW * 0.19, y: shoulderTop),
                   control2: CGPoint(x: headCx + shoulderW / 2, y: shoulderTop - cardH * 0.02))
shoulders.closeSubpath()
ctx.addPath(shoulders)
ctx.fillPath()
ctx.restoreGState()

// Crop marks: this app measures, it does not just crop. Two corners is enough at 40 px.
let markLen = S * 0.085, markW = S * 0.016, inset = S * 0.052
ctx.setStrokeColor(rgb(255, 196, 87))
ctx.setLineWidth(markW)
ctx.setLineCap(.square)
func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
    ctx.move(to: CGPoint(x: x + dx * markLen, y: y))
    ctx.addLine(to: CGPoint(x: x, y: y))
    ctx.addLine(to: CGPoint(x: x, y: y + dy * markLen))
    ctx.strokePath()
}
corner(cardRect.minX - inset, cardRect.maxY + inset, 1, -1)
corner(cardRect.maxX + inset, cardRect.minY - inset, -1, 1)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path) at \(Int(S))px")
