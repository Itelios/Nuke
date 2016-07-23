// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageManager

/**
The `ImageManager` class and related classes provide methods for loading, processing, caching.

`ImageManager` is also a pipeline that loads images using injectable dependencies, which makes it highly customizable. See https://github.com/kean/Nuke#design for more info.
*/
public class ImageManager {
    public var loader: ImageLoading
    public var cache: ImageCaching?
    
    private var executingTasks = Set<ImageTask>()
    private let lock = RecursiveLock()
    
    /// Returns all executing tasks.
    public var tasks: Set<ImageTask> {
        return lock.synced { executingTasks }
    }

    // MARK: Configuring Manager

    /// Initializes image manager with a given loader and cache.
    public init(loader: ImageLoading, cache: ImageCaching?) {
        self.loader = loader
        self.cache = cache
    }
    
    // MARK: Adding Tasks
    
    /**
     Creates a task with a given request. After you create a task, you start it by calling its resume method.
     
     The manager holds a strong reference to the task until it is either completes or get cancelled.
     */
    public func task(with request: ImageRequest, completion: ImageTask.Completion? = nil) -> ImageTask {
        let task = ImageTask(request: request, completion: completion)
        task.resumeHandler = { [weak self] task in
            self?.lock.sync { self?.run(task) }
        }
        task.cancellationHandler = { [weak self] task in
            self?.lock.sync { self?.cancel(task) }
        }
        return task
    }
    
    // MARK: Task Execution

    private func run(_ task: ImageTask) {
        if task.state == .suspended {
            task.state = .running

            executingTasks.insert(task)

            if task.request.memoryCachePolicy == .returnCachedImageElseLoad,
                let image = cache?.image(for: task.request) {
                complete(task, result: .success(image))
            } else {
                loadImage(for: task)
            }
        }
    }

    private func loadImage(for task: ImageTask) {
        task.loadTask = loader.loadImage(
            for: task.request,
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
                        if task.request.memoryCacheStorageAllowed {
                            self?.cache?.setImage(image, for: task.request)
                        }
                        self?.complete(task, result: .success(image))
                    case let .failure(err):
                        self?.complete(task, result: .failure(.loadingFailed(err)))
                    }
                }
            })
    }

    private func cancel(_ task: ImageTask) {
        if task.state == .suspended || task.state == .running {
            if task.state == .running {
                task.loadTask?.cancel()
                executingTasks.remove(task)
            }
            task.state = .cancelled
            dispatch(result: .failure(.cancelled), for: task)
        }
    }

    private func complete(_ task: ImageTask, result: ImageTask.ResultType) {
        if task.state == .running {
            task.state = .completed
            executingTasks.remove(task)
            dispatch(result: result, for: task)
        }
    }

    private func dispatch(result: ImageTask.ResultType, for task: ImageTask) {
        if let completion = task.completion {
            DispatchQueue.main.async {
                completion(task: task, result: result)
            }
        }
    }
}

/// Respresents image task.
public class ImageTask: Hashable {
    public enum Error: ErrorProtocol {
        case cancelled
        
        /// Some underlying error returned by class conforming to ImageLoading protocol
        case loadingFailed(Nuke.Error)
    }
    
    public typealias ResultType = Result<Image, Error>
    
    /// ImageTask completion block, gets called when task is either completed or cancelled.
    public typealias Completion = (task: ImageTask, result: ResultType) -> Void
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
    
    /// The request that task was created with.
    public let request: ImageRequest
    
    /// Return hash value for the receiver.
    public var hashValue: Int { return unsafeAddress(of: self).hashValue }
    
    
    // MARK: Obraining Task Progress
    
    /// Return current task progress. Initial value is (0, 0).
    public private(set) var progress = Progress()
    
    /// A progress closure that gets periodically during the lifecycle of the task.
    public var progressHandler: ((progress: Progress) -> Void)?
    
    
    // MARK: Controlling Task State
    
    public static let DidUpdateState = Notification.Name("com.github.kean.Nuke.ImageTask.DidUpdateState")
    
    /// The current state of the task.
    public private(set) var state: State = .suspended {
        didSet {
            NotificationCenter.default.post(name: ImageTask.DidUpdateState, object: self)
        }
    }
    
    /// Resumes the task if suspended. Resume methods are nestable.
    public func resume() { resumeHandler?(task: self) }
    private var resumeHandler: ((task: ImageTask) -> Void)?
    
    /// Cancels the task if it hasn't completed yet. Calls a completion closure with an error value of { ImageManagerErrorDomain, ImageManagerErrorCancelled }.
    public func cancel() { cancellationHandler?(task: self) }
    private var cancellationHandler: ((task: ImageTask) -> Void)?
    
    // MARK: Private
    
    private let completion: Completion?
    private var loadTask: Cancellable?
    
    private init(request: ImageRequest, completion: Completion?) {
        self.request = request
        self.completion = completion
    }
}

/// Compares two image tasks by reference.
public func ==(lhs: ImageTask, rhs: ImageTask) -> Bool {
    return lhs === rhs
}
