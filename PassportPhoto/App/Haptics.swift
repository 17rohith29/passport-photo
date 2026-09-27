import PhotoPipeline
import UIKit

/// Feedback at the three moments that carry information: a verdict arriving, a rejection, and a
/// save completing. Nothing fires for ordinary navigation, haptics that fire constantly stop
/// meaning anything.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }

    static func forVerdict(_ verdict: Verdict) {
        switch verdict {
        case .meetsRequirements: success()
        case .meetsRequirementsWithWarnings: warning()
        case .cannotUse: failure()
        }
    }
}
