import Foundation

/// Every algorithm constant, in one place. No country numbers live here, those are in `specs/`.
/// Each value says where it came from and which fixture pins it.
public struct Tuning: Sendable, Equatable {
    /// Crown = first row where the subject spans this fraction of face width. Skips flyaway
    /// strands that sit ~0.2 mm above the hair mass. LESSONS 2; pinned by IMG_0012 crown.
    public var crownSpanFraction: Double = 0.08

    /// Chin search walks this far below the landmark chin, as a fraction of brow-to-chin height.
    /// reference/python/chin.py; pinned by IMG_0012 chin.
    public var chinSearchAbove: Double = 0.05
    public var chinSearchBelow: Double = 0.22
    /// Half-width of the chin search strip, as a fraction of face width. LESSONS 1.
    public var chinStripHalfWidth: Double = 0.10
    /// Beard texture is "gone" at this fraction of the way from neck level back up to chin level.
    public var chinTextureThreshold: Float = 0.35
    /// Treated as bearded when chin texture exceeds this multiple of neck texture.
    public var beardedTextureRatio: Float = 1.8

    /// Cheek patches sit this fraction of face width inboard of the contour. LESSONS 5 warns the
    /// metric is fragile, so the placement is fixed here and calibrated on fixtures.
    public var cheekInset: Double = 0.08
    public var cheekPatchRadius: Double = 0.06
    /// The cheek region, as fractions of the eye-to-chin distance and of half the face width.
    /// A region median rather than two small patches, because the patch version inverted the
    /// ranking of IMG_0012 and IMG_0010.
    public var cheekRegionTop: Double = 0.10
    public var cheekRegionBottom: Double = 0.70
    public var cheekRegionInner: Double = 0.35
    /// Inset from the silhouette edge, so the region never samples hair, ear or background.
    public var cheekRegionEdgeInset: Double = 0.18

    /// Longest edge that segmentation and matte refinement work at. Those stages allocate several
    /// image-sized buffers, so running them at 24 MP costs hundreds of megabytes. The reference
    /// pipeline downsamples to 2600 px for the same reason. Only the matte is computed here; the
    /// photo itself is still composited and resampled at full resolution.
    public var matteWorkingSize: Int = 2048

    /// Matte edge band, in px at a 3088 px reference size: wide in hair, narrow on skin.
    /// LESSONS 9; scaled by image size.
    public var bandWidthHair: Double = 18
    public var bandWidthSkin: Double = 5
    public var bandReferenceSize: Double = 3088
    /// The band narrows across this fraction of face height below the brow.
    public var bandTransition: Double = 0.35

    /// Rim cleanup only touches low-saturation bright pixels inside the band. LESSONS 7.
    public var rimMaxSaturation: Float = 0.18
    public var rimMinValue: Float = 0.42
    /// How far out rim cleanup looks to confirm a pixel sits in a backdrop REGION rather than
    /// being an isolated highlight on a strand of hair.
    public var rimCoherenceReach: Int = 2
    /// Fraction of those neighbours that must also look like backdrop.
    public var rimCoherenceFraction: Double = 0.75

    /// Alpha below this is background, above is subject. Used before edge work.
    public var matteFloor: Float = 0.12
    public var matteScale: Float = 0.78

    /// Two-stage unsharp on the digital output. LESSONS 10; CLAHE was rejected.
    public var sharpenDigital: [SharpenPass] = [
        SharpenPass(radius: 1.3, amount: 0.28),
        SharpenPass(radius: 0.8, amount: 0.32),
    ]
    public var sharpenPrint: [SharpenPass] = [
        SharpenPass(radius: 1.1, amount: 0.20),
        SharpenPass(radius: 0.7, amount: 0.22),
    ]
    /// Sharpening applies only where alpha exceeds this; the anti-aliased rim is reverted.
    public var sharpenAlphaFloor: Float = 0.02

    /// JPEG quality search when hitting the spec's KB range. Never resize to hit it (LESSONS 4).
    public var jpegStartQuality: Double = 0.96
    public var jpegMinQuality: Double = 0.70
    public var jpegQualityStep: Double = 0.04

    /// faceIntegrity: fraction of the face oval allowed to be near-white. LESSONS 8.
    public var maxFaceWhitened: Double = 0.005
    public var faceWhiteThreshold: UInt8 = 235
    /// Least of the finished photo that must be backdrop.
    ///
    /// A backstop only: it exists to reject a "backdrop region" pieced out of a corner patch,
    /// which measured 4.6%. The real discrimination is done by the top-band median and by
    /// requiring the subject to reach the bottom edge, both of which are sharper and neither of
    /// which penalises a larger person.
    ///
    /// Calibrated against synthetic subjects across all eight specs, not just the fixture set:
    /// at 0.30 a China visa with ordinary hair volume measured 29.5% and would have been
    /// REJECTED, and Canada with a wide face, hair and broad shoulders measured 26.6%. Rejecting
    /// a real person for having hair is a worse failure than the one this guards against, so the
    /// floor sits well below the tightest realistic case (25.0%) while still being ten times the
    /// fake region it exists to catch.
    public var minBackdropCoverage: Double = 0.15

    public static let `default` = Tuning()

    public init() {}
}

public struct SharpenPass: Sendable, Equatable {
    public var radius: Double
    public var amount: Double

    public init(radius: Double, amount: Double) {
        self.radius = radius
        self.amount = amount
    }
}
