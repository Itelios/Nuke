// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

/// Defines constants that can be used to modify the way ImageManager interacts with the memory cache.
public enum ImageRequestMemoryCachePolicy {
    /// Return memory cached image corresponding the request. If there is no existing image in the memory cache, the image manager continues with the request.
    case ReturnCachedImageElseLoad
    
    /// Reload using ignoring memory cached images. Doesn't affect on-disk caching.
    case ReloadIgnoringCachedImage
}

/// Encapsulates image request parameters.
public struct ImageRequest {
    /// The URL request that the image request was created with.
    public var URLRequest: NSURLRequest

    /// Specifies whether loaded image should be stored into memory cache. Default value is true.
    public var memoryCacheStorageAllowed = true
    
    /// The request memory cachce policy. Default value is .ReturnCachedImageElseLoad.
    public var memoryCachePolicy = ImageRequestMemoryCachePolicy.ReturnCachedImageElseLoad

    #if os(OSX)
    /// Filter to be applied to the image. Use ImageProcessorComposition to compose multiple filters. Empty by default.
        public var processors: [ImageProcessing]
    #else
    /// Filter to be applied to the image. Use ImageProcessorComposition to compose multiple filters. By default contains an instance of ImageDecompressor.
        public var processors: [ImageProcessing] = [ImageDecompressor()]
    #endif
    
    #if !os(OSX)
    /// The relative priority at which you’d like a host to handle the task. The priority is used when creating an underlying NSURLSessionTask.
    public var priority: Float?
    #endif
    
    /// Allows users to pass some custom info alongside the request.
    public var userInfo: Any?
    
    /// Initializes request with a URL.
    public init(URL: NSURL) {
        self.URLRequest = NSURLRequest(URL: URL)
    }
    
    /// Initializes request with a URL request.
    public init(URLRequest: NSURLRequest) {
        self.URLRequest = URLRequest
    }
}

extension ImageRequest {
    var processor: ImageProcessing? {
        return processors.isEmpty ? nil : ImageProcessorComposition(processors: processors)
    }
}
