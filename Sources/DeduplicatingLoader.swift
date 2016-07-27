// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Deduplicates equivalent requests.
///
/// If you attempt to load an image using `DeduplicatingLoader` more than once
/// before the initial load is complete, it would merge duplicate tasks. 
/// The image would be loaded only once, yet both completion and progress
/// handlers will get called.
public final class DeduplicatingLoader<LoaderType: Loading>: Loading {
    public typealias ObjectType = LoaderType.ObjectType

    private let loader: LoaderType
    private let equator: RequestEquating
    private var tasks = [RequestKey: DeduplicatorTask<ObjectType>]()
    private let queue = DispatchQueue(label: "\(domain).DeduplicatingLoader")
    
    /// Initializes the `DeduplicatingLoader` instance with the underlying
    /// `loader` used for loading images, and the request `equator`.
    /// - parameter loader: Underlying loader used for loading images.
    /// - parameter equator: Compares requests for equivalence.
    /// `RequestLoadingEquator()` be default.
    public init(with loader: LoaderType, equator: RequestEquating = RequestLoadingEquator()) {
        self.loader = loader
        self.equator = equator
    }
    
    /// Loads an object for the given request.
    public func loadObject(for request: Request, progress: LoadingProgress?, completion: (result: Result<ObjectType, AnyError>) -> Void) -> Cancellable {
        return queue.sync {
            // Find existing or create a new task (manages multiple handlers)
            let key = RequestKey(request, equator: equator)
            var task: DeduplicatorTask<ObjectType>! = tasks[key]
            if task == nil {
                task = DeduplicatorTask<ObjectType>()
                tasks[key] = task
            }
            // Create a handler for a current request
            let handler = DeduplicatorHandler(progress, completion, cancellation: {
                [weak self, weak task] handler in
                if let task = task {
                    self?.remove(handler: handler, from: task, key: key)
                }
            })
            
            // Register the handler and start the request if necessary
            task.handlers.append(handler)
            if task.subtask == nil { // deferred till the end
                task.subtask = loadObject(for: request, task: task, key: key)
            }
            return handler
        }
    }

    private func loadObject(for request: Request, task: DeduplicatorTask<ObjectType>, key: RequestKey) -> Cancellable {
        return loader.loadObject(
            for: request,
            progress: { [weak self, weak task] completed, total in
                _ = self?.queue.sync {
                    task?.handlers.forEach { $0.progress?(completed: completed, total: total) }
                }
            },
            completion: { [weak self, weak task] result in
                _ = self?.queue.sync {
                    task?.handlers.forEach { $0.completion(result: result) }
                    self?.tasks[key] = nil
                }
            })
    }
    
    private func remove(handler: DeduplicatorHandler<ObjectType>, from task: DeduplicatorTask<ObjectType>, key: RequestKey) {
        queue.sync {
            if let index = task.handlers.index(where: { $0 === handler }) {
                task.handlers.remove(at: index)
                if task.handlers.isEmpty {
                    task.subtask?.cancel()
                    tasks[key] = nil
                }
            }
        }
    }

}

// FIXME: we still can't have nested types inside a generic type
final class DeduplicatorHandler<T>: Cancellable {
    let progress: LoadingProgress?
    // FIXME: I can't use LoadingCompletion<T> here because of the segfault.
    let completion: (result: Result<T, AnyError>) -> Void
    let cancellation: (DeduplicatorHandler<T>) -> Void

    init(_ progress: LoadingProgress?, _ completion: (result: Result<T, AnyError>) -> Void, cancellation: (DeduplicatorHandler<T>) -> Void) {
        self.progress = progress
        self.completion = completion
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation(self)
    }
}

// FIXME: we still can't have nested types inside a generic type
final class DeduplicatorTask<T> {
    var handlers = [DeduplicatorHandler<T>]()
    var subtask: Cancellable?
}
