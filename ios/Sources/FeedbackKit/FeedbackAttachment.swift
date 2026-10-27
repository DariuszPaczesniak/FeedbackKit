#if os(iOS)
import UIKit

/// A single screenshot attachment for a bug report, optionally marked up
/// with freehand drawing (see `AttachmentMarkupView`). `original` is the
/// unmodified captured/picked image; `markup`, when present, is the
/// flattened (original + drawing) composite that should be shown/shared
/// instead.
struct FeedbackAttachment: Identifiable {
    let id = UUID()
    var original: UIImage
    var markup: UIImage?

    var displayImage: UIImage { markup ?? original }
}
#endif
