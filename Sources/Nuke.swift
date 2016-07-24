// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(OSX)
    import AppKit.NSImage
    /// Alias for NSImage
    public typealias Image = NSImage
#else
    import UIKit.UIImage
    /// Alias for UIImage
    public typealias Image = UIImage
#endif

/// Creates a task with the given `URL` using shared `Manager`.
/// After you create a task, start it using `resume()` method.
public func task(with url: URL, completion: Manager.Completion? = nil) -> Task {
    return Manager.shared.task(with: url, completion: completion)
}

/// Creates a task with the given `Request` using shared `Manager`.
/// After you create a task, start it using `resume()` method.
/// - parameter options: `Options()` be default.
public func task(with request: Request, options: Manager.Options = Manager.Options(), completion: Manager.Completion? = nil) -> Task {
    return Manager.shared.task(with: request, options: options, completion: completion)
}

// MARK: - Manager Extensions

/// `Manager` extensions.
public extension Manager {
    /// Creates a task with with given request.
    /// After you create a task, start it using `resume()` method.
    func task(with url: URL, completion: Completion? = nil) -> Task {
        return task(with: Request(url: url), completion: completion)
    }
    
    /// Shared `Manager` instance.
    ///
    /// Shared manager is created with `DataLoader()`, `ImageDataDecoder()`,
    /// and `Cache()`. Loader is wrapped into `DeduplicatingLoader`.
    public static var shared: Manager = {
        let loader = Loader(dataLoader: DataLoader(), dataDecoder: ImageDataDecoder())
        return Manager(loader: DeduplicatingLoader(loader: loader), cache: Cache())
    }()
}

// MARK: - Result

/// `Result` is the type that represent either success or a failure.
public enum Result<V, E: ErrorProtocol> {
    case success(V)
    case failure(E)
    
    init(value: V?, error: @autoclosure () -> E) {
        self = value.map(Result.success) ?? .failure(error())
    }
}

public extension Result {
    public var value: V? {
        switch self {
        case let .success(val): return val
        default: return nil
        }
    }
    
    public var error: E? {
        switch self {
        case let .failure(err): return err
        default: return nil
        }
    }
    
    public var isSuccess: Bool {
        return value != nil
    }
}

// MARK: - Progress

/// Represents progress.
public struct Progress {
    /// Completed unit count.
    public var completed: Int64 = 0
    
    /// Total unit count.
    public var total: Int64 = 0
    
    /// The fraction of overall work completed.
    /// If the total unit count is 0 fraction completed is also 0.
    public var fractionCompleted: Double {
        return total == 0 ? 0.0 : Double(completed) / Double(total)
    }
}

// MARK: - Cancellable

public protocol Cancellable {
    func cancel()
}

// MARK: - AnyError

/// Type erased error.
public struct AnyError: ErrorProtocol {
    public var cause: ErrorProtocol
    public init(_ cause: ErrorProtocol) {
        self.cause = (cause as? AnyError)?.cause ?? cause
    }
}
