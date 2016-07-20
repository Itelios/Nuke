// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Convenience

/// Creates a task with a given URL. After you create a task, start it using resume method.
public func task(with url: URL, completion: ImageTaskCompletion? = nil) -> ImageTask {
    return ImageManager.shared.task(with: url, completion: completion)
}

/// Creates a task with a given request. After you create a task, start it using resume method.
public func task(with request: ImageRequest, completion: ImageTaskCompletion? = nil) -> ImageTask {
    return ImageManager.shared.task(with: request, completion: completion)
}

/**
 Prepares images for the given requests for later use.

 When you call this method, `ImageManager` starts to load and cache images for the given requests. `ImageManager` caches images with the exact target size, content mode, and filters. At any time afterward, you can create tasks with equivalent requests.
 */
public func startPreheating(for requests: [ImageRequest]) {
    ImageManager.shared.startPreheating(for: requests)
}

/// Stop preheating for the given requests. The request parameters should match the parameters used in `startPreheatingImages` method.
public func stopPreheating(for requests: [ImageRequest]) {
    ImageManager.shared.stopPreheating(for: requests)
}

/// Stops all preheating tasks.
public func stopPreheating() {
    ImageManager.shared.stopPreheating()
}


// MARK: - ImageManager (Convenience)

/// Convenience methods for ImageManager.
public extension ImageManager {
    /// Creates a task with a given request. For more info see `task(with: _)` methpd.
    func task(with url: URL, completion: ImageTaskCompletion? = nil) -> ImageTask {
        return self.task(with: ImageRequest(url: url), completion: completion)
    }
}


// MARK: - ImageManager (Shared)

/// Manages shared ImageManager instance.
public extension ImageManager {
    private static var manager = ImageManager.makeDefaultManager()
    
    public static func makeDefaultManager() -> ImageManager {
        let dataLoader = DataLoader()
        let dataDecoder = DataDecoder()
        let loader = ImageLoader(dataLoader: dataLoader, dataDecoder: dataDecoder)

        let cache = ImageCache()
        let manager = ImageManager(loader: loader, cache: cache)
        manager.onInvalidateAndCancel = {
            dataLoader.session.invalidateAndCancel()
        }
        manager.onRemoveAllCachedImages = {
            cache.removeAllImages()
            dataLoader.session.configuration.urlCache?.removeAllCachedResponses()
        }
        return manager
    }
    
    private static let lock = RecursiveLock()
    
    /// The shared image manager. This property and all other `ImageManager` APIs are thread safe.
    public class var shared: ImageManager {
        set {
            lock.lock()
            manager = newValue
            lock.unlock()
        }
        get {
            lock.lock()
            let result = manager
            lock.unlock()
            return result
        }
    }
}


// MARK - Progress

/// Represents image task progress.
public struct Progress {
    /// Completed unit count.
    public var completed: Int64 = 0
    
    /// Total unit count.
    public var total: Int64 = 0
}

public extension Progress {
    /// The fraction of overall work completed. If the total unit count is 0 fraction completed is also 0.
    public var fractionCompleted: Double {
        return total == 0 ? 0.0 : Double(completed) / Double(total)
    }
}


// MARK - Cancellable

public protocol Cancellable {
    func cancel()
}
