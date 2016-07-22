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
    private var executingTasks = Set<ImageTask>()
    private let lock = RecursiveLock()
    private var taskIdentifier: Int = 0
    private var nextTaskIdentifier: Int {
        return lock.synced {
            taskIdentifier += 1
            return taskIdentifier
        }
    }
    public var loader: ImageLoading
    public var cache: ImageCaching?
    
    public var onDidUpdateTasks: ((Set<ImageTask>) -> Void)?
    
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
        let task = ImageTask(request: request, identifier: nextTaskIdentifier, completion: completion)
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

            didStartExecuting(task)

            if task.request.memoryCachePolicy == .returnCachedImageElseLoad,
                let image = image(for: task.request) {
                complete(task, result: .success(image))
            } else {
                loadImage(for: task)
            }
        }
    }

    private func loadImage(for task: ImageTask) {
        task.loadTask = loader.loadImage(
            for: task.request,
            progress: { progress in
                DispatchQueue.main.async {
                    task.progress = progress
                    task.progressHandler?(progress: progress)
                }
            },
            completion: { [weak self] result in
                switch result {
                case let .success(image):
                    if task.request.memoryCacheStorageAllowed {
                        self?.setImage(image, for: task.request)
                    }
                    self?.complete(task, result: .success(image))
                case let .failure(err):
                    self?.complete(task, result: .failure(.loadingFailed(err)))
                }
            })
    }

    private func cancel(_ task: ImageTask) {
        if task.state == .suspended || task.state == .running {
            if task.state == .running {
                task.loadTask?.cancel()
                didStopExecuting(task)
            }
            task.state = .cancelled
            dispatch(result: .failure(.cancelled), for: task)
        }
    }

    private func complete(_ task: ImageTask, result: ImageTask.ResultType) {
        if task.state == .running {
            task.state = .completed
            didStopExecuting(task)
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

    private func didStartExecuting(_ task: ImageTask) {
        executingTasks.insert(task)
        onDidUpdateTasks?(executingTasks)
    }

    private func didStopExecuting(_ task: ImageTask) {
        executingTasks.remove(task)
        onDidUpdateTasks?(executingTasks)
    }

    // MARK: Memory Caching
    
    /// Returns image from the memory cache.
    public func image(for request: ImageRequest) -> Image? {
        return cache?.image(for: makeCacheKey(request))
    }
    
    /// Stores image into the memory cache.
    public func setImage(_ image: Image, for request: ImageRequest) {
        cache?.setImage(image, for: makeCacheKey(request))
    }
    
    /// Removes image from the memory cache.
    public func removeImage(for request: ImageRequest) {
        cache?.removeImage(for: makeCacheKey(request))
    }
    
    private func makeCacheKey(_ request: ImageRequest) -> ImageRequestKey {
        return ImageRequestKey(request: request) { [weak self] in
            return self?.isCacheEquivalent($0.request, to: $1.request) ?? false
        }
    }

    // MARK: Request Equivalence

    public func isLoadEquivalent(_ a: ImageRequest, to b: ImageRequest) -> Bool {
        return isLoadEquivalent(a.urlRequest, to: b.urlRequest) &&
            isCacheEquivalent(a, to: b)
    }
    
    public func isLoadEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        return a.url == b.url &&
            a.cachePolicy == b.cachePolicy &&
            a.timeoutInterval == b.timeoutInterval &&
            a.networkServiceType == b.networkServiceType &&
            a.allowsCellularAccess == b.allowsCellularAccess
    }

    public func isCacheEquivalent(_ a: ImageRequest, to b: ImageRequest) -> Bool {
        return a.urlRequest.url == b.urlRequest.url &&
            isEquivalent(a.processor, rhs: b.processor)
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
    public var hashValue: Int { return identifier }
    
    /// Uniquely identifies the task within an image manager.
    public let identifier: Int
    
    
    // MARK: Obraining Task Progress
    
    /// Return current task progress. Initial value is (0, 0).
    public private(set) var progress = Progress()
    
    /// A progress closure that gets periodically during the lifecycle of the task.
    public var progressHandler: ((progress: Progress) -> Void)?
    
    
    // MARK: Controlling Task State
    
    /// The current state of the task.
    public private(set) var state: State = .suspended
    
    /// Resumes the task if suspended. Resume methods are nestable.
    public func resume() { resumeHandler?(task: self) }
    private var resumeHandler: ((task: ImageTask) -> Void)?
    
    /// Cancels the task if it hasn't completed yet. Calls a completion closure with an error value of { ImageManagerErrorDomain, ImageManagerErrorCancelled }.
    public func cancel() { cancellationHandler?(task: self) }
    private var cancellationHandler: ((task: ImageTask) -> Void)?
    
    // MARK: Private
    
    private let completion: Completion?
    private var loadTask: Cancellable?
    
    private init(request: ImageRequest, identifier: Int, completion: Completion?) {
        self.request = request
        self.identifier = identifier
        self.completion = completion
    }
}

/// Compares two image tasks by reference.
public func ==(lhs: ImageTask, rhs: ImageTask) -> Bool {
    return lhs === rhs
}
