// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// ImageTask completion block, gets called when task is either completed or cancelled.
public typealias ImageTaskCompletion = (ImageTask, ImageResponse) -> Void

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
    private var executingTasks = Set<ImageManagerTask>()
    private var preheatingTasks = [ImageRequestKey: ImageManagerTask]()
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
    public func task(with request: ImageRequest, completion: ImageTaskCompletion? = nil) -> ImageTask {
        return ImageManagerTask(delegate: self, request: request, identifier: nextTaskIdentifier, completion: completion)
    }
    
    // MARK: FSM (ImageTaskState)
    
    private func setState(_ state: ImageTaskState, for task: ImageManagerTask)  {
        if task.isValid(nextState: state) {
            transitionStateAction(from: task.state, to: state, task: task)
            task.state = state
            enterStateAction(to: state, task: task)
        }
    }
    
    private func transitionStateAction(from: ImageTaskState, to: ImageTaskState, task: ImageManagerTask) {
        if from == .running && to == .cancelled {
            task.cancellable?.cancel()
        }
    }
    
    private func enterStateAction(to state: ImageTaskState, task: ImageManagerTask) {
        switch state {
        case .running:
            if task.request.memoryCachePolicy == .returnCachedImageElseLoad {
                if let image = image(for: task.request) {
                    task.response = ImageResponse.success(image)
                    setState(.completed, for: task)
                    return
                }
            }
            executingTasks.insert(task) // Register task until it's completed or cancelled.
            task.cancellable = loader.loadImage(
                for: task.request,
                progress: { [weak self] completed, total in
                    self?.updateProgress(ImageTaskProgress(completed: completed, total: total), for: task)
                },
                completion: { [weak self] image, error in
                    self?.complete(task, image: image, error: error)
            })
        case .cancelled:
            task.response = ImageResponse.failure(errorWithCode(.cancelled))
            fallthrough
        case .completed:
            executingTasks.remove(task)
            setNeedsExecutePreheatingTasks()
            
            assert(task.response != nil)
            let response = task.response!
            if let completion = task.completion {
                DispatchQueue.main.async {
                    completion(task, response)
                }
            }
        default: break
        }
    }

    private func updateProgress(_ progress: ImageTaskProgress, for task: ImageTask) {
        DispatchQueue.main.async {
            task.progress = progress
            task.progressHandler?(progress: progress)
        }
    }

    private func complete(_ task: ImageTask, image: Image?, error: ErrorProtocol?) {
        perform {
            if let image = image, task.request.memoryCacheStorageAllowed {
                setImage(image, for: task.request)
            }

            let task = task as! ImageManagerTask
            if task.state == .running {
                if let image = image {
                    task.response = ImageResponse.success(image)
                } else {
                    task.response = ImageResponse.failure(error ?? errorWithCode(.unknown))
                }
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
                    preheatingTasks[key] = ImageManagerTask(delegate: self, request: $0, identifier: nextTaskIdentifier) { [weak self] _ in
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
    public var tasks: (executingTasks: Set<ImageTask>, preheatingTasks: Set<ImageTask>) {
        return performed {
            return (self.executingTasks, Set(self.preheatingTasks.values))
        }
    }


    // MARK: Misc
    
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
    
    private func cancel<T: Sequence where T.Iterator.Element == ImageManagerTask>(_ tasks: T) {
        tasks.forEach { setState(.cancelled, for: $0) }
    }
}

extension ImageManager: ImageManagerTaskDelegate {
    
    // MARK: ImageManager: ImageManagerTaskDelegate
    
    private func resume(_ task: ImageManagerTask) {
        perform { setState(.running, for: task) }
    }
    
    private func cancel(_ task: ImageManagerTask) {
        perform { setState(.cancelled, for: task) }
    }
}

// MARK: - ImageManagerTask

private protocol ImageManagerTaskDelegate {
    func resume(_ task: ImageManagerTask)
    func cancel(_ task: ImageManagerTask)
}

private class ImageManagerTask: ImageTask {
    let delegate: ImageManagerTaskDelegate
    let completion: ImageTaskCompletion?
    var cancellable: Cancellable?
    
    init(delegate: ImageManagerTaskDelegate, request: ImageRequest, identifier: Int, completion: ImageTaskCompletion?) {
        self.delegate = delegate
        self.completion = completion
        super.init(request: request, identifier: identifier)
    }
    
    override func resume() {
        delegate.resume(self)
    }
    
    override func cancel() {
        delegate.cancel(self)
    }

    func isValid(nextState: ImageTaskState) -> Bool {
        switch (self.state) {
        case .suspended: return (nextState == .running || nextState == .cancelled)
        case .running: return (nextState == .completed || nextState == .cancelled)
        default: return false
        }
    }
}
