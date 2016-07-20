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
public protocol ImageMemoryCaching {
    /// Returns an image for the specified key.
    func imageForKey(key: ImageRequestKey) -> Image?

    /// Stores the image for the specified key.
    func setImage(image: Image, forKey key: ImageRequestKey)

    /// Removes the cached image for the specified key.
    func removeImageForKey(key: ImageRequestKey)
}

/// Auto purging memory cache that uses NSCache as its internal storage.
public class ImageMemoryCache: ImageMemoryCaching {
    deinit {
        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }
    
    // MARK: Configuring Cache
    
    /// The internal memory cache.
    public let cache: NSCache

    /// Initializes the receiver with a given memory cache.
    public init(cache: NSCache) {
        self.cache = cache
        #if os(iOS) || os(tvOS)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ImageMemoryCache.didReceiveMemoryWarning(_:)), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    /// Initializes cache with the recommended cache total limit.
    public convenience init() {
        let cache = NSCache()
        cache.totalCostLimit = ImageMemoryCache.recommendedCostLimit()
        #if os(OSX)
            cache.countLimit = 100
        #endif
        self.init(cache: cache)
    }
    
    /// Returns recommended cost limit in bytes.
    public class func recommendedCostLimit() -> Int {
        let physicalMemory = NSProcessInfo.processInfo().physicalMemory
        let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }
    
    // MARK: Managing Cached Responses

    /// Returns an image for the specified key.
    public func imageForKey(key: ImageRequestKey) -> Image? {
        return cache.objectForKey(key) as? Image
    }

    /// Stores the image for the specified key.
    public func setImage(image: Image, forKey key: ImageRequestKey) {
        cache.setObject(image, forKey: key, cost: costFor(image))
    }

    /// Removes the cached image for the specified key.
    public func removeImageForKey(key: ImageRequestKey) {
        cache.removeObjectForKey(key)
    }
    
    /// Removes all cached images.
    public func removeAllCachedImages() {
        cache.removeAllObjects()
    }

    // MARK: Subclassing Hooks
    
    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public func costFor(image: Image) -> Int {
        #if os(OSX)
            return 1
        #else
            return CGImageGetBytesPerRow(image.CGImage) * CGImageGetHeight(image.CGImage)
        #endif
    }
    
    dynamic private func didReceiveMemoryWarning(notification: NSNotification) {
        cache.removeAllObjects()
    }
}
