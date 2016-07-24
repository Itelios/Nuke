// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ReusingLoader: Loading {
    private let loader: Loading
    private let equator: RequestEquating
    private var tasks = [RequestKey: Task]()
    private let lock = RecursiveLock()
    
    public init(loader: Loading, equator: RequestEquating = RequestLoadingEquator()) {
        self.loader = loader
        self.equator = equator
    }
    
    /// Loads image for the given request.
    public func loadImage(for request: Request, progress: LoadingProgress? = nil, completion: LoadingCompletion) -> Cancellable {
        return lock.synced {
            let key = RequestKey(request: request, equator: equator)
            var task: Task! = tasks[key]
            if task == nil {
                task = Task()
                tasks[key] = task
            }
            let handler = Handler(progress: progress, completion: completion, cancellation: { [weak self, weak task] handler in
                if let task = task {
                    self?.unsibscribe(handler: handler, from: task, key: key)
                }
            })
            task.handlers.append(handler)
            if task.underlyingTask == nil { // defer creation of task till the end
                task.underlyingTask = loadImage(for: request, task: task, key: key)
            }
            return handler
        }
    }
    
    private func loadImage(for request: Request, task: Task, key: RequestKey) -> Cancellable {
        return loader.loadImage(
            for: request,
            progress: { [weak self, weak task] completed, total in
                self?.lock.sync {
                    task?.handlers.forEach { $0.progress?(completed: completed, total: total) }
                }
            },
            completion: { [weak self, weak task] result in
                self?.lock.sync {
                    task?.handlers.forEach { $0.completion(result: result) }
                    self?.tasks[key] = nil
                }
            })
    }
    
    private func unsibscribe(handler: Handler, from task: Task, key: RequestKey) {
        lock.sync {
            if let index = task.handlers.index(where: { $0 === handler }) {
                task.handlers.remove(at: index)
                if task.handlers.count == 0 {
                    task.underlyingTask?.cancel()
                    tasks[key] = nil
                }
            }
        }
    }
    
    class Handler: Cancellable {
        let progress: LoadingProgress?
        let completion: LoadingCompletion
        let cancellation: (Handler) -> Void
        
        init(progress: LoadingProgress?, completion: LoadingCompletion, cancellation: (Handler) -> Void) {
            self.progress = progress
            self.completion = completion
            self.cancellation = cancellation
        }
        
        func cancel() {
            cancellation(self)
        }
    }
    
    /// Manages multiple handlers for the same inner task.
    class Task {
        var handlers = [Handler]()
        var underlyingTask: Cancellable?
    }
}
