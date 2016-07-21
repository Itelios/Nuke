// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Convenience

/// Creates a task with a given URL. After you create a task, start it using resume method.
public func task(with url: URL, completion: ImageManager.Task.Completion? = nil) -> ImageManager.Task {
    return ImageManager.shared.task(with: url, completion: completion)
}

/// Creates a task with a given request. After you create a task, start it using resume method.
public func task(with request: ImageRequest, completion: ImageManager.Task.Completion? = nil) -> ImageManager.Task {
    return ImageManager.shared.task(with: request, completion: completion)
}


// MARK: - ImageManager (Convenience)

/// Convenience methods for ImageManager.
public extension ImageManager {
    /// Creates a task with a given request. For more info see `task(with: _)` methpd.
    func task(with url: URL, completion: ImageManager.Task.Completion? = nil) -> ImageManager.Task {
        return self.task(with: ImageRequest(url: url), completion: completion)
    }
}


// MARK: - ImageManager (Shared)

/// Shared ImageManager instance.
public extension ImageManager {
    public static var shared: ImageManager = {
        let dataLoader = DataLoader()
        let dataDecoder = DataDecoder()
        let loader = ImageLoader(dataLoader: dataLoader, dataDecoder: dataDecoder)
        
        let cache = ImageCache()
        return ImageManager(loader: loader, cache: cache)
    }()
}


// MARK: - Progress

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


// MARK: - Cancellable

public protocol Cancellable {
    func cancel()
}


// MARK: Error

/// Allows us to use ErrorProtocol in Nuke.Result without
/// resorting to generics. Dynamic typing makes much more
/// sense at this point, because generics are under-developed
/// and type-safety in error handling in Nuke isn't crucial.
public struct Error: ErrorProtocol {
    public var error: ErrorProtocol
    public init(_ error: ErrorProtocol) {
        self.error = error
    }
}

// MARK: - Result

/// Result is the type that represent either success (.ok) or a failure (.error).
public enum Result<V, E: ErrorProtocol> {
    case ok(V)
    case error(E)
    
    public init(value: V?, error: @autoclosure () -> E) {
        self = value.map(Result.ok) ?? .error(error())
    }
}

public extension Result {
    public var value: V? {
        switch self {
        case let .ok(val): return val
        default: return nil
        }
    }
    
    public var error: E? {
        switch self {
        case let .error(err): return err
        default: return nil
        }
    }
    
    public var isOk: Bool {
        switch self {
        case .ok(_): return true
        default: return false
        }
    }
}
