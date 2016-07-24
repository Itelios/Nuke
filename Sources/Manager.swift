// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - Manager

/**
The `Manager` class and related classes provide methods for loading, processing, caching images.

`Manager` is also a pipeline that loads images using injectable dependencies, which makes it highly customizable. See https://github.com/kean/Nuke#design for more info.
*/
public class Manager {
    public var loader: Loading
    public var cache: Caching?
    
    private var executingTasks = Set<Task>()
    private let lock = RecursiveLock()
    
    /// Returns all executing tasks.
    public var tasks: Set<Task> {
        return lock.synced { executingTasks }
    }

    // MARK: Configuring Manager

    /// Initializes image manager with a given loader and cache.
    public init(loader: Loading, cache: Caching?) {
        self.loader = loader
        self.cache = cache
    }
    
    // MARK: Making Tasks
    
    public typealias Completion = (task: Task, result: Result<Image, Task.Error>) -> Void
    
    /**
     Creates a task with a given request. After you create a task, you start it by calling its resume method.
     
     The manager holds a strong reference to the task until it is either completes or get cancelled.
     */
    public func task(with request: Request, completion: Completion? = nil) -> Task {
        let task = Task()
        let ctx = Context(request: request, completion: completion)
        task.resumeHandler = { [weak self] task in
            self?.lock.sync { self?.run(task, ctx: ctx) }
        }
        task.cancellationHandler = { [weak self] task in
            self?.lock.sync { self?.cancel(task, ctx: ctx) }
        }
        return task
    }
    
    // MARK: Task Execution

    private func run(_ task: Task, ctx: Context) {
        if task.state == .suspended {
            task.state = .running

            executingTasks.insert(task)

            if ctx.request.memoryCachePolicy == .returnCachedObjectElseLoad,
                let image = cache?.image(for: ctx.request) {
                complete(task, result: .success(image), ctx: ctx)
            } else {
                loadImage(for: task, ctx: ctx)
            }
        }
    }

    private func loadImage(for task: Task, ctx: Context) {
        ctx.loadTask = loader.loadImage(
            for: ctx.request,
            progress: { completed, total in
                DispatchQueue.main.async {
                    task.progress = Progress(completed: completed, total: total)
                    task.progressHandler?(progress: task.progress)
                }
            },
            completion: { [weak self] result in
                self?.lock.sync {
                    switch result {
                    case let .success(image):
                        if ctx.request.memoryCacheStorageAllowed {
                            self?.cache?.setImage(image, for: ctx.request)
                        }
                        self?.complete(task, result: .success(image), ctx: ctx)
                    case let .failure(err):
                        self?.complete(task, result: .failure(.loadingFailed(err)), ctx: ctx)
                    }
                }
            })
    }

    private func cancel(_ task: Task, ctx: Context) {
        if task.state == .suspended || task.state == .running {
            if task.state == .running {
                ctx.loadTask?.cancel()
                executingTasks.remove(task)
            }
            task.state = .cancelled
            dispatch(result: .failure(.cancelled), for: task, ctx: ctx)
        }
    }

    private func complete(_ task: Task, result: Result<Image, Task.Error>, ctx: Context) {
        if task.state == .running {
            task.state = .completed
            executingTasks.remove(task)
            dispatch(result: result, for: task, ctx: ctx)
        }
    }

    private func dispatch(result: Result<Image, Task.Error>, for task: Task, ctx: Context) {
        if let completion = ctx.completion {
            DispatchQueue.main.async {
                completion(task: task, result: result)
            }
        }
    }
}

/// Task execution context.
private class Context {
    var request: Request
    var completion: Manager.Completion?
    var loadTask: Cancellable?
    
    init(request: Request, completion: Manager.Completion?) {
        self.request = request
        self.completion = completion
    }
}

/// Respresents image task.
public class Task: Hashable {
    public enum Error: ErrorProtocol {
        case cancelled
        
        /// Some underlying error returned by class conforming to Loading protocol
        case loadingFailed(AnyError)
    }
    
    /**
     The state of the task. Allowed transitions include:
     - suspended -> [running, cancelled]
     - running -> [cancelled, completed]
     - cancelled -> []
     - completed -> []
     */
    public enum State {
        case suspended, running, cancelled, completed
    }
    
    // MARK: Obtainig General Task Information
    
    /// Return hash value for the receiver.
    public var hashValue: Int { return unsafeAddress(of: self).hashValue }
    
    
    // MARK: Obraining Task Progress
    
    /// Return current task progress. Initial value is (0, 0).
    public private(set) var progress = Progress()
    
    /// A progress closure that gets periodically during the lifecycle of the task.
    public var progressHandler: ((progress: Progress) -> Void)?
    
    
    // MARK: Controlling Task State
    
    public static let DidUpdateState = Notification.Name("com.github.kean.Nuke.Task.DidUpdateState")
    
    /// The current state of the task.
    public private(set) var state: State = .suspended {
        didSet {
            NotificationCenter.default.post(name: Task.DidUpdateState, object: self)
        }
    }
    
    /// Resumes the task if suspended. Resume methods are nestable.
    public func resume() { resumeHandler?(task: self) }
    private var resumeHandler: ((task: Task) -> Void)?
    
    /// Cancels the task if it hasn't completed yet.
    public func cancel() { cancellationHandler?(task: self) }
    private var cancellationHandler: ((task: Task) -> Void)?
}

/// Compares two image tasks by reference.
public func ==(lhs: Task, rhs: Task) -> Bool {
    return lhs === rhs
}
