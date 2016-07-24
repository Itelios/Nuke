// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages preheating (also known as prefetching, precaching) of images.
///
/// When you are working with many images, a `Preheater` can prepare images in
/// the background in order to eliminate delays when you later request
/// individual images. For example, use a `Preheater` when you want to populate
/// a collection view or similar UI with thumbnails.
///
/// To start preheating images call `startPreheating(for:)` method. When you
/// need an individual image just create a `Task` using `Manager`.
/// When preheating is no logner necessary call `stopPreheating(for:)` method.
///
/// `Preheater` guarantees that its tasks never interfere with regular tasks
/// created for individual images which always run first.
public class Preheater {
    
    /// Maximum number of concurrent preheating tasks. 3 be default.
    public var maxConcurrentTaskCount = 3

    private let manager: Manager
    private let equator: RequestEquating
    private var map = [RequestKey: Task]()
    private var tasks = [Task]() // we need to keep tasks in order
    private var needsToResumeTasks = false
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Preheater.Queue", attributes: DispatchQueueAttributes.serial)

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Initializes the `Preheater` instance with the `manager` used for
    /// loading images, and the request `equator`.
    /// - parameter manager: The manager used for loading images.
    /// - parameter equator: Compares requests for equivalence.
    /// `RequestLoadingEquator()` be default.
    public init(manager: Manager, equator: RequestEquating = RequestLoadingEquator()) {
        self.manager = manager
        self.equator = equator
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsResumeTasks), name: Task.DidUpdateState, object: nil)
    }

    /// Prepares images for the given requests for later use.
    ///
    /// When you call this method, `Preheater` starts to load and cache images
    /// for the given requests. At any time afterward, you can create tasks
    /// for individual images with equivalent requests.
    public func startPreheating(for requests: [Request]) {
        queue.async {
            requests.forEach { self.startPreheating(for: $0) }
            self.setNeedsResumeTasks()
        }
    }
    
    private func startPreheating(for request: Request) {
        let key = RequestKey(request, equator: equator)
        if map[key] == nil { // Create just one task per request
            let task = manager.task(with: request) { [weak self] task, _ in
                self?.map[key] = nil
                if let idx = self?.tasks.index(of: task) {
                    self?.tasks.remove(at: idx) // FIXME: use OrderedSet(Map)
                }
            }
            map[key] = task
            tasks.append(task)
        }
    }
    
    /// Cancels image preparation for the given requests.
    public func stopPreheating(for requests: [Request]) {
        queue.async {
            requests.forEach {
                self.map[RequestKey($0, equator: self.equator)]?.cancel()
            }
        }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.map.values.forEach { $0.cancel() }
        }
    }

    dynamic private func setNeedsResumeTasks() {
        queue.async {
            if !self.needsToResumeTasks {
                self.needsToResumeTasks = true
                self.queue.after(when: .now() + 0.2) { // after 200 ms
                    self.resumeTasks()
                }
            }
        }
    }

    private func resumeTasks() {
        var executingTaskCount = manager.tasks.count
        for task in tasks {
            if executingTaskCount >= maxConcurrentTaskCount { break }
            if task.state == .suspended {
                task.resume()
                executingTaskCount += 1
            }
        }
        needsToResumeTasks = false
    }
}
