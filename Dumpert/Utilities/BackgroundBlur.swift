import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Pre-bakes a blurred, slightly desaturated, downsampled background bitmap.
///
/// We blur ONCE here instead of using SwiftUI's live `.blur` modifier. A live
/// `.blur` is a CALayer gaussian filter that re-rasterizes the full-screen 4K
/// image on every layout pass; under memory pressure that blocked the main
/// thread for >2 s and got the app watchdog-killed (Sentry DUMPERT-APPLE-TV-4).
/// Baking a small bitmap up front removes that filter from the render loop.
enum BackgroundBlur {
    // CIContext creation is expensive and the context is thread-safe, so share one.
    nonisolated(unsafe) private static let context = CIContext()

    /// Returns a blurred copy of `image`. `maxDimension` and `radius` are visual
    /// tuning knobs (radius is in the downsampled pixel space). The result is
    /// upscaled to fill the screen by the caller, which adds extra smoothing.
    /// ponytail: knobs left for visual calibration, defaults match the old look.
    static func apply(to image: UIImage,
                      maxDimension: CGFloat = 480,
                      radius: CGFloat = 12) -> UIImage {
        guard let cg = image.cgImage else { return image }
        var ci = CIImage(cgImage: cg)

        // Downsample first: the output is blurred anyway, so a small bitmap keeps
        // memory and render cost tiny (the hang device had ~12 MB free RAM).
        let longEdge = max(ci.extent.width, ci.extent.height)
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1
        if scale < 1 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let cropExtent = ci.extent

        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.8
        ci = color.outputImage ?? ci

        // Clamp before the gaussian so edges stay opaque (blur shrinks the extent).
        let clamp = CIFilter.affineClamp()
        clamp.inputImage = ci
        clamp.transform = .identity
        ci = clamp.outputImage ?? ci

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ci
        blur.radius = Float(radius)
        ci = blur.outputImage ?? ci

        guard let out = context.createCGImage(ci, from: cropExtent) else { return image }
        return UIImage(cgImage: out)
    }
}
