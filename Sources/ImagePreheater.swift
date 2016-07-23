// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ImagePreheater {
    
    /// Default value is 3.
    public var maxConcurrentTaskCount = 3

    private let manager: ImageManager
    private let equator: ImageRequestEquating
    private var map = [ImageRequestKey: ImageTask]()
    private var tasks = [ImageTask]() // we need ordered tasks, map's not enough
    private var needsToResumeTasks = false
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePreheater.Queue", attributes: DispatchQueueAttributes.serial)

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public init(manager: ImageManager, equator: ImageRequestEquating = ImageRequestLoadingEquator()) {
        self.manager = manager
        self.equator = equator
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsResumeTasks), name: ImageTask.DidUpdateState, object: nil)
    }

    /**
     Prepares images for the given requests for later use.

     When you call this method, ImageManager starts to load and cache images for the given requests. ImageManager caches images with the exact target size, content mode, and filters. At any time afterward, you can create tasks with equivalent requests.
     */
    public func startPreheating(for requests: [ImageRequest]) {
        queue.async {
            requests.forEach {
                self.startPreheating(for: $0)
            }
            self.setNeedsResumeTasks()
        }
    }
    
    private func startPreheating(for request: ImageRequest) {
        let key = ImageRequestKey(request: request, equator: equator)
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
    
    /// Stop preheating for the given requests. The request parameters should match the parameters used in startPreheatingImages method.
    public func stopPreheating(for requests: [ImageRequest]) {
        queue.async {
            requests.forEach {
                self.map[ImageRequestKey(request: $0, equator: self.equator)]?.cancel()
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
