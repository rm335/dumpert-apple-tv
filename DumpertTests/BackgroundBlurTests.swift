import Foundation
import UIKit
import Testing
@testable import Dumpert

@Suite("Background Blur")
struct BackgroundBlurTests {

    /// Builds a solid-color source image at a given size.
    private func solidImage(_ size: CGSize, color: UIColor = .red) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test("Downsamples a large image to the max dimension")
    func downsamplesLargeImage() {
        let source = solidImage(CGSize(width: 1920, height: 1080))
        let result = BackgroundBlur.apply(to: source, maxDimension: 480)
        // cgImage pixels, not points — fixture is @1x so pixels == points here.
        let longEdge = max(result.size.width, result.size.height)
        #expect(longEdge <= 480)
        #expect(result.cgImage != nil)
    }

    @Test("Keeps small images at or below the max dimension")
    func keepsSmallImage() {
        let source = solidImage(CGSize(width: 200, height: 120))
        let result = BackgroundBlur.apply(to: source, maxDimension: 480)
        #expect(max(result.size.width, result.size.height) <= 480)
        #expect(result.cgImage != nil)
    }
}
