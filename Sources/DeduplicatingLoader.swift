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
public final class DeduplicatingLoader: Loading {
    private let loader: Loading
    private let equator: RequestEquating
    private var tasks = [RequestKey: Task]()
    private let queue = DispatchQueue(label: "\(domain).DeduplicatingLoader")
    
    /// Initializes the `DeduplicatingLoader` instance with the underlying
    /// `loader` used for loading images, and the request `equator`.
    /// - parameter loader: Underlying loader used for loading images.
    /// - parameter equator: Compares requests for equivalence.
    /// `RequestLoadingEquator()` be default.
    public init(with loader: Loading, equator: RequestEquating = RequestLoadingEquator()) {
        self.loader = loader
        self.equator = equator
    }
    
    /// Loads an image for the given request.
    public func loadImage(for request: Request, progress: LoadingProgress? = nil, completion: LoadingCompletion) -> Cancellable {
        return queue.sync {
            // Find existing or create a new task (manages multiple handlers)
            let key = RequestKey(request, equator: equator)
            var task: Task! = tasks[key]
            if task == nil {
                task = Task()
                tasks[key] = task
            }
            
            // Create a handler for a current request
            let handler = Handler(progress, completion, cancellation: {
                [weak self, weak task] handler in
                if let task = task {
                    self?.remove(handler: handler, from: task, key: key)
                }
            })
            
            // Register the handler and start the request if necessary
            task.handlers.append(handler)
            if task.subtask == nil { // deferred till the end
                task.subtask = loadImage(for: request, task: task, key: key)
            }
            return handler
        }
    }
    
    private func loadImage(for request: Request, task: Task, key: RequestKey) -> Cancellable {
        return loader.loadImage(
            for: request,
            progress: { [weak self, weak task] completed, total in
                _ = self?.queue.sync {
                    task?.handlers.forEach { $0.progress?(completed: completed, total: total) }
                }
            },
            completion: { [weak self, weak task] result in
                self?.queue.sync {
                    task?.handlers.forEach { $0.completion(result: result) }
                    self?.tasks[key] = nil
                }
            })
    }
    
    private func remove(handler: Handler, from task: Task, key: RequestKey) {
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
    
    final class Handler: Cancellable {
        let progress: LoadingProgress?
        let completion: LoadingCompletion
        let cancellation: (Handler) -> Void
        
        init(_ progress: LoadingProgress?, _ completion: LoadingCompletion, cancellation: (Handler) -> Void) {
            self.progress = progress
            self.completion = completion
            self.cancellation = cancellation
        }
        
        func cancel() {
            cancellation(self)
        }
    }

    final class Task {
        var handlers = [Handler]()
        var subtask: Cancellable?
    }
}
