// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

#if os(watchOS)
    import WatchKit
#endif

/// Decodes data into images.
public protocol DataDecoding {
    /// Decodes data into an image object.
    func decode(data: Data, response: URLResponse) -> Image?
}


private let lock = Lock()

/// Decodes data into an image object. Image scale is set to the scale of the main screen.
public class DataDecoder: DataDecoding {
    /// Initializes the receiver.
    public init() {}

    /// Decodes data into an image object using native methods.
    public func decode(data: Data, response: URLResponse) -> Image? {
        // Image initializers are not thread safe:
        // - https://github.com/AFNetworking/AFNetworking/issues/2572
        // - https://github.com/Alamofire/AlamofireImage/issues/75
        return lock.synced {
            #if os(OSX)
                return NSImage(data: data)
            #else
                return UIImage(data: data, scale: imageScale)
            #endif
        }
    }

    #if !os(OSX)
    /// The scale used when creating an image object. Return the scaleM of the main screen.
    public var imageScale: CGFloat {
        #if os(iOS) || os(tvOS)
            return UIScreen.main().scale
        #else
            return WKInterfaceDevice.current().screenScale
        #endif
    }
    #endif
}

/// Composes multiple image decoders.
public class DataDecoderComposition: DataDecoding {
    /// Image decoders that the receiver was initialized with.
    public let decoders: [DataDecoding]

    /// Composes multiple image decoders.
    public init(decoders: [DataDecoding]) {
        self.decoders = decoders
    }

    /// Decoders are applied in an order in which they are present in the decoders array. The decoding stops when one of the decoders produces an image.
    public func decode(data: Data, response: URLResponse) -> Image? {
        for decoder in decoders {
            if let image = decoder.decode(data: data, response: response) {
                return image
            }
        }
        return nil
    }
}
