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
    func image(for key: ImageRequestKey) -> Image?

    /// Stores the image for the specified key.
    func setImage(_ image: Image, for key: ImageRequestKey)

    /// Removes the cached image for the specified key.
    func removeImage(for key: ImageRequestKey)
}

/// Auto purging memory cache that uses NSCache as its internal storage.
public class ImageCache: ImageCaching {
    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self, name: .UIApplicationDidReceiveMemoryWarning, object: nil)
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
    public func image(for key: ImageRequestKey) -> Image? {
        return cache.object(forKey: WrappedKey(val: key)) as? Image
    }

    /// Stores the image for the specified key.
    public func setImage(_ image: Image, for key: ImageRequestKey) {
        cache.setObject(image, forKey: WrappedKey(val: key), cost: cost(for: image))
    }

    /// Removes the cached image for the specified key.
    public func removeImage(for key: ImageRequestKey) {
        cache.removeObject(forKey: WrappedKey(val: key))
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

private class WrappedKey<T: Hashable>: NSObject {
    let val: T
    init(val: T) {
        self.val = val
    }

    override var hash: Int {
        return val.hashValue
    }

    override func isEqual(_ other: AnyObject?) -> Bool {
        return val == (other as? WrappedKey)?.val
    }
}
