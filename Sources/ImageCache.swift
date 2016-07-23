// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

/// Provides in-memory storage for image.
public protocol ImageCaching {
    /// Returns an image for the specified key.
    func image(for request: ImageRequest) -> Image?

    /// Stores the image for the specified key.
    func setImage(_ image: Image, for request: ImageRequest)
    
    /// Removes the cached image for the specified key.
    func removeImage(for request: ImageRequest)
}

/// Auto purging memory cache that uses NSCache as its internal storage.
public class ImageCache: ImageCaching, ImageRequestEquating {
    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    // MARK: Configuring Cache
    
    /// The internal memory cache.
    public let cache: Cache<AnyObject, AnyObject>

    /// Initializes the receiver with a given memory cache.
    public init(cache: Cache<AnyObject, AnyObject> = ImageCache.makeDefaultCache()) {
        self.cache = cache
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(ImageCache.didReceiveMemoryWarning(_:)), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
        #endif
    }
    
    /// Initializes cache with the recommended cache total limit.
    private static func makeDefaultCache() -> Cache<AnyObject, AnyObject> {
        let cache = Cache<AnyObject, AnyObject>()
        cache.totalCostLimit = {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
            let limit = physicalMemory / UInt64(1 / ratio)
            return limit > UInt64(Int.max) ? Int.max : Int(limit)
        }()
        return cache
    }
    
    // MARK: Managing Cached Images

    /// Returns an image for the specified key.
    public func image(for request: ImageRequest) -> Image? {
        return cache.object(forKey: makeKey(for: request)) as? Image
    }

    /// Stores the image for the specified key.
    public func setImage(_ image: Image, for request: ImageRequest) {
        cache.setObject(image, forKey: makeKey(for: request), cost: cost(for: image))
    }

    /// Removes the cached image for the specified key.
    public func removeImage(for request: ImageRequest) {
        cache.removeObject(forKey: makeKey(for: request))
    }

    private func makeKey(for request: ImageRequest) -> Wrapped<ImageRequestKey> {
        return Wrapped(val: ImageRequestKey(request: request, equator: self))
    }
    
    // MARK: ImageRequestEquating
    
    public func isEqual(_ a: ImageRequest, to b: ImageRequest) -> Bool {
        return a.urlRequest.url == b.urlRequest.url &&
            isEquivalent(a.processor, rhs: b.processor)
    }
    
    // MARK: Subclassing Hooks
    
    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public func cost(for image: Image) -> Int {
        #if os(OSX)
            return 1
        #else
            guard let cgImage = image.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        #endif
    }
    
    dynamic private func didReceiveMemoryWarning(_ notification: Notification) {
        cache.removeAllObjects()
    }
}

/// Allows to use Swift Hashable objects with NSCache
private class Wrapped<T: Hashable>: NSObject {
    let val: T
    init(val: T) {
        self.val = val
    }

    override var hash: Int {
        return val.hashValue
    }

    override func isEqual(_ other: AnyObject?) -> Bool {
        return val == (other as? Wrapped)?.val
    }
}
