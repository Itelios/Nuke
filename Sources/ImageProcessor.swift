// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

// MARK: - ImageProcessing

/**
Performs image processing.

Types that implement `ImageProcessing` protocol should either use one of the default implementations of `isEquivalent(_:)` method or provide their own implementation, which is required to cache processed images.
*/
public protocol ImageProcessing {
    /// Returns processed image.
    func process(_ image: Image) -> Image?

    /// Compares two processors for equivalence. Two processors are equivalent if they produce the same image for the same input. For more info see the extensions that provide default implementations of this method.
    func isEquivalent(_ other: ImageProcessing) -> Bool
}

public extension ImageProcessing {
    /// Returns true if both processors are instances of the same class. Use this implementation when your filter doesn't have any parameters.
    public func isEquivalent(_ other: ImageProcessing) -> Bool {
        return other is Self
    }
}

public extension ImageProcessing where Self: Equatable {
    /// Compares processors using == function.
    public func isEquivalent(_ other: ImageProcessing) -> Bool {
        return (other as? Self) == self
    }
}


// MARK: - ImageProcessorComposition

/// Composes multiple image processors.
public class ImageProcessorComposition: ImageProcessing, Equatable {
    /// Image processors that the receiver was initialized with.
    public let processors: [ImageProcessing]

    /// Composes multiple image processors.
    public init(processors: [ImageProcessing]) {
        self.processors = processors
    }

    /// Processes the given image by applying each processor in an order in which they are present in the processors array. If one of the processors fails to produce an image the processing stops and nil is returned.
    public func process(_ input: Image) -> Image? {
        return processors.reduce(input as Image!) { image, processor in
            return image != nil ? processor.process(image!) : nil
        }
    }
}

/// Returns true if both compositions have the same number of processors, and the processors are pairwise-equivalent.
public func ==(lhs: ImageProcessorComposition, rhs: ImageProcessorComposition) -> Bool {
    return lhs.processors.count == rhs.processors.count &&
        !(zip(lhs.processors, rhs.processors).contains{ !$0.isEquivalent($1) })
}


func isEquivalent(_ lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?): return l.isEquivalent(r)
    case (nil, nil): return true
    default: return false
    }
}

#if !os(OSX)

    /// An option for how to resize the image to the target size.
    public enum ImageContentMode {
        /// Scales the image so that it completely fills the target size. Maintains image aspect ratio. Images are not clipped.
        case aspectFill

        /// Scales the image so that its larger dimension fits the target size. Maintains image aspect ratio.
        case aspectFit
    }

    /// Size to pass when requesting the original image available for a request (image won't be resized).
    public let ImageMaximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    // MARK: - ImageDecompressor

    /**
    Decompresses and scales input images.

    If the image size is bigger then the given target size (in pixels) it is resized to either fit or fill target size (see ImageContentMode enum for more info). Image is scaled maintaining aspect ratio.

    Decompression and scaling are performed in a single pass which improves performance and reduces memory usage.
    */
    public class ImageDecompressor: ImageProcessing, Equatable {
        /// Target size in pixels. Default value is ImageMaximumSize.
        public let targetSize: CGSize

        /// An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
        public let contentMode: ImageContentMode

        /**
         Initializes the receiver with target size and content mode.

         - parameter targetSize: Target size in pixels. Default value is ImageMaximumSize.
         - parameter contentMode: An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
         */
        public init(targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .aspectFill) {
            self.targetSize = targetSize
            self.contentMode = contentMode
        }

        /// Decompressed the input image.
        public func process(_ image: Image) -> Image? {
            return decompress(image, targetSize: targetSize, contentMode: contentMode)
        }
    }

    /// Returns true if both decompressors have the same `targetSize` and `contentMode`.
    public func ==(lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
        return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
    }

    private func decompress(_ image: UIImage, targetSize: CGSize, contentMode: ImageContentMode) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }
        let bitmapSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scaleHor = targetSize.width / bitmapSize.width
        let scaleVert = targetSize.height / bitmapSize.height
        let scale = contentMode == .aspectFill ? max(scaleHor, scaleVert) : min(scaleHor, scaleVert)
        return decompress(image, scale: CGFloat(min(scale, 1)))
    }

    private func decompress(_ image: UIImage, scale: CGFloat) -> UIImage {
        guard let imageRef = image.cgImage else { return image }
        
        let size = CGSize(width: round(scale * CGFloat(imageRef.width)), height: round(scale * CGFloat(imageRef.height)))

        // For more info see:
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        let alphaInfo: CGImageAlphaInfo = isOpaque(imageRef) ? .noneSkipLast : .premultipliedLast
        let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue)

        guard let contextRef = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo.rawValue) else {
            return image
        }
        contextRef.draw(in: CGRect(origin: CGPoint.zero, size: size), image: imageRef)
        guard let decompressedImageRef = contextRef.makeImage() else {
            return image
        }
        return UIImage(cgImage: decompressedImageRef, scale: image.scale, orientation: image.imageOrientation)
    }

    private func isOpaque(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }
#endif
