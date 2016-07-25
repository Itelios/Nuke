// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Mananges creating and execution of image tasks.
///
/// `Manager` loads images using injectable dependencies conforming to `Loading`,
/// and `Caching` protocols.
public class Manager {
    public var loader: Loading
    public var cache: Caching?
    
    private var executingTasks = Set<Task>()
    private let lock = RecursiveLock()
    
    /// Returns all executing tasks.
    public var tasks: Set<Task> { return lock.synced { executingTasks } }

    // MARK: Configuring Manager

    /// Initializes `Manager` instance with the given loader and cache.
    public init(loader: Loading, cache: Caching?) {
        self.loader = loader
        self.cache = cache
    }
        
    // MARK: Making Tasks

    public typealias Completion = (task: Task, response: Task.Response) -> Void
    
    /// Creates a task with the given `Request`. After you create a task, 
    /// start it using `resume()` method. The completion closure gets called
    /// on the main thread when tasks either completes or gets cancelled.
    /// - parameter options: `Options()` be default.
    ///
    /// The manager maintains a strong reference to the task until it finishes
    /// or fails.
    public func task(with request: Request, options: Options = Options(), completion: Completion? = nil) -> Task {
        let task = Task()
        let ctx = Context(request: request, options: options, completion: completion)
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

            if ctx.options.memoryCachePolicy == .returnCachedObjectElseLoad,
                let image = cache?.image(for: ctx.request) {
                complete(task, response: .success(image), ctx: ctx)
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
                    task.progress = (completed: completed, total: total)
                    task.progressHandler?(completed: completed, total: total)
                }
            },
            completion: { [weak self] result in
                self?.lock.sync {
                    switch result {
                    case let .success(image):
                        if ctx.options.memoryCacheStorageAllowed {
                            self?.cache?.setImage(image, for: ctx.request)
                        }
                        self?.complete(task, response: .success(image), ctx: ctx)
                    case let .failure(err):
                        self?.complete(task, response: .failure(.loadingFailed(err)), ctx: ctx)
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
            dispatch(response: .failure(.cancelled), for: task, ctx: ctx)
        }
    }

    private func complete(_ task: Task, response: Task.Response, ctx: Context) {
        if task.state == .running {
            task.state = .completed
            executingTasks.remove(task)
            dispatch(response: response, for: task, ctx: ctx)
        }
    }

    private func dispatch(response: Task.Response, for task: Task, ctx: Context) {
        if let completion = ctx.completion {
            DispatchQueue.main.async { completion(task: task, response: response) }
        }
    }
    
    /// A set of options affecting how `Manager` deliveres an image.
    public struct Options {
        /// Defines the way `Manager` interacts with the memory cache.
        public enum MemoryCachePolicy {
            /// Return memory cached image corresponding the request.
            /// If there is no existing image in the memory cache, 
            /// the image manager continues with the request.
            case returnCachedObjectElseLoad
            
            /// Reload using ignoring memory cached objects.
            case reloadIgnoringCachedObject
        }
        
        /// Specifies whether loaded object should be stored into memory cache.
        /// `true` be default.
        public var memoryCacheStorageAllowed = true
        
        /// `.returnCachedObjectElseLoad` by default.
        public var memoryCachePolicy = MemoryCachePolicy.returnCachedObjectElseLoad

        public init() {}
    }
    
    /// Task execution context.
    private class Context {
        var request: Request
        var options: Options
        var completion: Completion?
        var loadTask: Cancellable?
        
        init(request: Request, options: Options, completion: Completion?) {
            self.request = request
            self.options = options
            self.completion = completion
        }
    }
}

/// Respresents the image task.
///
/// Task is always in one of four states: `suspended`, `running`, `cancelled` or
/// `completed`. The task is always created in a `suspended` state. You can use
/// the corresponding `resume()` and `cancel()` methods to control the task's 
/// state. It's always safe to call these methods, no matter in which state
/// the task is currently in.
public class Task: Hashable {
    public typealias Response = Result<Image, Error>
    
    public enum Error: ErrorProtocol {
        /// `Task` was cancelled.
        case cancelled
        
        /// Some underlying error returned by `Loading` instance
        case loadingFailed(AnyError)
    }
    
    /// The state of the `Task`. Allowed transitions:
    /// - suspended -> [running, cancelled]
    /// - running -> [cancelled, completed]
    public enum State {
        case suspended, running, cancelled, completed
    }
    
    // MARK: Obtaining Task Progress
    
    /// Return current task progress. Initial value is (0, 0).
    public private(set) var progress = (completed: Int64, total: Int64)(0, 0)
    
    /// A progress closure, gets called periodically.
    public var progressHandler: ((completed: Int64, total: Int64) -> Void)?
    
    // MARK: Controlling Task State
    
    public static let DidUpdateState = Notification.Name("com.github.kean.Nuke.Task.DidUpdateState")
    
    /// The current state of the task.
    public private(set) var state: State = .suspended {
        didSet {
            NotificationCenter.default.post(name: Task.DidUpdateState, object: self)
        }
    }
    
    /// Resumes the task if suspended.
    public func resume() { resumeHandler?(task: self) }
    private var resumeHandler: ((task: Task) -> Void)?
    
    /// Cancels the task if it hasn't completed yet.
    public func cancel() { cancellationHandler?(task: self) }
    private var cancellationHandler: ((task: Task) -> Void)?
    
    public var hashValue: Int { return unsafeAddress(of: self).hashValue }
}

/// Compares two image tasks by reference.
public func ==(lhs: Task, rhs: Task) -> Bool {
    return lhs === rhs
}
