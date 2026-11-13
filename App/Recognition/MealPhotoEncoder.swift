// SPDX-License-Identifier: MPL-2.0

import PocketNutritionCore
import UIKit

/// Turns a picked or taken photo into the JPEG sent for analysis.
///
/// The image is redrawn into a fresh bitmap, so nothing of the original file survives: no EXIF, no GPS
/// location, no camera details. Only the pixels, scaled so the longest side is at most
/// `recognitionPhotoMaxSide`.
enum MealPhotoEncoder {
    static let quality: CGFloat = 0.8

    static func jpeg(from image: UIImage) -> Data? {
        guard let target = recognitionPhotoTargetSize(
            width: Double(image.size.width), height: Double(image.size.height)
        ) else { return nil }
        let size = CGSize(width: target.width, height: target.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // `draw(in:)` applies the image orientation, so the pixels come out upright.
        let redrawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.jpegData(compressionQuality: quality)
    }
}
