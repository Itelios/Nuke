// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/**
The domain used for creating all ImageManager errors.

The image manager would produce either errors in ImageManagerErrorDomain or errors in NSURLErrorDomain (which are not wrapped).
 */
public let ImageManagerErrorDomain = "Nuke.ImageManagerErrorDomain"

/// The image manager error codes.
public enum ImageManagerErrorCode: Int {
    /// Returned when the image manager encountered an error that it cannot interpret.
    case unknown = -15001

    /// Returned when the image task gets cancelled.
    case cancelled = -15002
    
    /// Returned when the image manager fails decode image data.
    case decodingFailed = -15003
    
    /// Returned when the image manager fails to process image data.
    case processingFailed = -15004
}

// MARK: - ImageManager

/**
The `ImageManager` class and related classes provide methods for loading, processing, caching and preheating images.

`ImageManager` is also a pipeline that loads images using injectable dependencies, which makes it highly customizable. See https://github.com/kean/Nuke#design for more info.
*/
public class ImageManager {
    private var executingTasks = Set<Task>()
    private var preheatingTasks = [ImageRequestKey: Task]()
    private let lock = RecursiveLock()
    private var invalidated = false
    private var needsToExecutePreheatingTasks = false
    private var taskIdentifier: Int = 0
    private var nextTaskIdentifier: Int {
        return performed {
            taskIdentifier += 1
            return taskIdentifier
        }
    }
    private var loader: ImageLoading
    private var cache: ImageCaching?
    
    public var onInvalidateAndCancel: ((Void) -> Void)?
    public var onRemoveAllCachedImages: ((Void) -> Void)?
    
    // MARK: Configuring Manager

    /// Default value is 2.
    public var maxConcurrentPreheatingTaskCount = 2

    /// Initializes image manager with a given configuration. ImageManager becomes a delegate of the ImageLoader.
    public init(loader: ImageLoading, cache: ImageCaching?) {
        self.loader = loader
        self.cache = cache
    }
    
    // MARK: Adding Tasks
    
    /**
     Creates a task with a given request. After you create a task, you start it by calling its resume method.
     
     The manager holds a strong reference to the task until it is either completes or get cancelled.
     */
    public func task(with request: ImageRequest, completion: Task.Completion? = nil) -> Task {
        return Task(manager: self, request: request, identifier: nextTaskIdentifier, completion: completion)
    }
    
    // MARK: FSM (ImageTask.State)
    
    private func setState(_ state: Task.State, for task: Task)  {
        if task.isValid(nextState: state) {
            transitionStateAction(from: task.state, to: state, task: task)
            task.state = state
            enterStateAction(to: state, task: task)
        }
    }
    
    private func transitionStateAction(from: Task.State, to: Task.State, task: Task) {
        if from == .running && to == .cancelled {
            task.cancellable?.cancel()
        }
    }
    
    private func enterStateAction(to state: Task.State, task: Task) {
        switch state {
        case .running:
            if task.request.memoryCachePolicy == .returnCachedImageElseLoad {
                if let image = image(for: task.request) {
                    task.result = .ok(image)
                    setState(.completed, for: task)
                    return
                }
            }
            executingTasks.insert(task) // Register task until it's completed or cancelled.
            task.cancellable = loader.loadImage(
                for: task.request,
                progress: { [weak self] completed, total in
                    self?.updateProgress(Progress(completed: completed, total: total), for: task)
                },
                completion: { [weak self] result in
                    self?.complete(task, result: result)
            })
        case .cancelled:
            task.result = .error(errorWithCode(.cancelled))
            fallthrough
        case .completed:
            executingTasks.remove(task)
            setNeedsExecutePreheatingTasks()
            
            assert(task.result != nil)
            let result = task.result!
            if let completion = task.completion {
                DispatchQueue.main.async {
                    completion(task: task, result: result)
                }
            }
        default: break
        }
    }

    private func updateProgress(_ progress: Progress, for task: Task) {
        DispatchQueue.main.async {
            task.progress = progress
            task.progressHandler?(progress: progress)
        }
    }

    private func complete(_ task: Task, result: Task.ResultType) {
        perform {
            if let image = result.value, task.request.memoryCacheStorageAllowed {
                setImage(image, for: task.request)
            }

            if task.state == .running {
                task.result = result
                setState(.completed, for: task)
            }
        }
    }
    
    // MARK: Preheating
    
    /**
    Prepares images for the given requests for later use.
    
    When you call this method, ImageManager starts to load and cache images for the given requests. ImageManager caches images with the exact target size, content mode, and filters. At any time afterward, you can create tasks with equivalent requests.
    */
    public func startPreheating(for requests: [ImageRequest]) {
        perform {
            requests.forEach {
                let key = makePreheatKey($0)
                if preheatingTasks[key] == nil { // Don't create more than one task for the equivalent requests.
                    preheatingTasks[key] = task(with: $0) { [weak self] _ in
                        self?.preheatingTasks[key] = nil
                    }
                }
            }
            setNeedsExecutePreheatingTasks()
        }
    }
    
    private func makePreheatKey(_ request: ImageRequest) -> ImageRequestKey {
        return makeCacheKey(request)
    }
    
    /// Stop preheating for the given requests. The request parameters should match the parameters used in startPreheatingImages method.
    public func stopPreheating(for requests: [ImageRequest]) {
        perform {
            cancel(requests.flatMap {
                return preheatingTasks[makePreheatKey($0)]
            })
        }
    }
    
    /// Stops all preheating tasks.
    public func stopPreheating() {
        perform { cancel(preheatingTasks.values) }
    }
    
    private func setNeedsExecutePreheatingTasks() {
        if !needsToExecutePreheatingTasks && !invalidated {
            needsToExecutePreheatingTasks = true
            DispatchQueue.main.after(when: DispatchTime.now() + Double(Int64((0.15 * Double(NSEC_PER_SEC)))) / Double(NSEC_PER_SEC)) {
                [weak self] in self?.perform {
                    self?.executePreheatingTasksIfNeeded()
                }
            }
        }
    }
    
    private func executePreheatingTasksIfNeeded() {
        needsToExecutePreheatingTasks = false
        var executingTaskCount = executingTasks.count
        // FIXME: Use sorted dictionary
        for task in (preheatingTasks.values.sorted { $0.identifier < $1.identifier }) {
            if executingTaskCount > maxConcurrentPreheatingTaskCount {
                break
            }
            if task.state == .suspended {
                setState(.running, for: task)
                executingTaskCount += 1
            }
        }
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
        return ImageRequestKey(request: request) { [weak self] lhs, rhs in
            return self?.isCacheEquivalent(lhs.request, rhs.request) ?? false
        }
    }
    
    private func isCacheEquivalent(_ lhs: ImageRequest, _ rhs: ImageRequest) -> Bool {
        return lhs.urlRequest.url == rhs.urlRequest.url && isEquivalent(lhs.processor, rhs: rhs.processor)
    }
    
    // MARK: Misc
    
    /// Cancels all outstanding tasks and then invalidates the manager. New image tasks may not be resumed.
    public func invalidateAndCancel() {
        perform {
            cancel(executingTasks)
            preheatingTasks.removeAll()
            invalidated = true
            onInvalidateAndCancel?()
        }
    }
    
    /// Calls onRemoveAllCachedImages closure, default implementation does nothing.
    public func removeAllCachedImages() {
        perform {
            onRemoveAllCachedImages?()
        }
    }
    
    /// Returns all executing tasks and all preheating tasks. Set with executing tasks might contain currently executing preheating tasks.
    public var tasks: (executingTasks: Set<Task>, preheatingTasks: Set<Task>) {
        return performed {
            return (self.executingTasks, Set(self.preheatingTasks.values))
        }
    }


    // MARK: Private
    
    private func perform(_ closure: @noescape (Void) -> Void) {
        lock.lock()
        if !invalidated { closure() }
        lock.unlock()
    }
    
    private func performed<T>(_ closure: @noescape (Void) -> T) -> T {
        lock.lock()
        let result = closure()
        lock.unlock()
        return result
    }
    
    private func cancel<T: Sequence where T.Iterator.Element == Task>(_ tasks: T) {
        tasks.forEach { setState(.cancelled, for: $0) }
    }
}

public extension ImageManager {
    
    // MARK: Task Management
    
    private func resume(_ task: Task) {
        perform { setState(.running, for: task) }
    }
    
    private func cancel(_ task: Task) {
        perform { setState(.cancelled, for: task) }
    }
    
    // MARK: Task
    
    /// Respresents image task.
    public class Task: Hashable {
        public typealias ResultType = Result<Image, NSError>
        
        /// ImageTask completion block, gets called when task is either completed or cancelled.
        public typealias Completion = (task: Task, result: Result<Image, NSError>) -> Void
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
        
        /// The response which is set when task is either completed or cancelled.
        public private(set) var result: ResultType?
        
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
        public func resume() {
            manager?.resume(self)
        }
        
        /// Cancels the task if it hasn't completed yet. Calls a completion closure with an error value of { ImageManagerErrorDomain, ImageManagerErrorCancelled }.
        public func cancel() {
            manager?.cancel(self)
        }
        
        // MARK: Private
        
        private weak var manager: ImageManager?
        private let completion: Completion?
        private var cancellable: Cancellable?
        
        private init(manager: ImageManager, request: ImageRequest, identifier: Int, completion: Completion?) {
            self.manager = manager
            self.request = request
            self.identifier = identifier
            self.completion = completion
        }
        
        private func isValid(nextState: State) -> Bool {
            switch (self.state) {
            case .suspended: return (nextState == .running || nextState == .cancelled)
            case .running: return (nextState == .completed || nextState == .cancelled)
            default: return false
            }
        }
    }
}

/// Compares two image tasks by reference.
public func ==(lhs: ImageManager.Task, rhs: ImageManager.Task) -> Bool {
    return lhs === rhs
}
