import Foundation

/// Vision-backed face analysis and segmentation, plus pure measurement code.
///
/// Filled in at M2 (`VisionFaceAnalyzer`, `ImageMetrics`, `ChinRefiner`) and
/// M3 (`VisionSubjectSegmenter`, `MatteRefiner`, `CrownFinder`). The target exists now so the
/// dependency direction (PhotoPipeline -> PhotoAnalysis -> SpecKit) is fixed from M0.
public enum PhotoAnalysis {
    public static let milestone = "M0: target scaffolded"
}
