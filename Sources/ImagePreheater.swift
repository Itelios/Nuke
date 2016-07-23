// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ImagePreheater: ImageRequestEquating {
    private let manager: ImageManager

    /// Default value is 2.
    public var maxConcurrentTaskCount = 2

    private var map: [ImageRequestKey: ImageTask] = [:]
    private var tasks = [ImageTask]() // we need ordered tasks, map's not enough
    private var needsToResumeTasks = false
    private let queue = DispatchQueue(label: "ImagePreheater.Queue", attributes: DispatchQueueAttributes.serial)

    public init(manager: ImageManager) {
        self.manager = manager
        manager.onDidUpdateTasks = { [weak self] _ in
            self?.setNeedsResumeTasks()
        }
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
        let key = makePreheatKey(request)
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

    private func makePreheatKey(_ request: ImageRequest) -> ImageRequestKey {
        return ImageRequestKey(request: request, equator: self)
    }
    
    /// Stop preheating for the given requests. The request parameters should match the parameters used in startPreheatingImages method.
    public func stopPreheating(for requests: [ImageRequest]) {
        queue.async {
            requests.forEach {
                self.map[self.makePreheatKey($0)]?.cancel()
            }
        }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.map.values.forEach { $0.cancel() }
        }
    }

    private func setNeedsResumeTasks() {
        if !needsToResumeTasks {
            needsToResumeTasks = true
            queue.after(when: .now() + 0.2) { // after 200 ms
                self.resumeTasks()
            }
        }
    }

    private func resumeTasks() {
        var executingTaskCount = manager.tasks.count
        for task in tasks {
            if executingTaskCount >= maxConcurrentTaskCount {
                break
            }
            if task.state == .suspended {
                task.resume()
                executingTaskCount += 1
            }
        }
        needsToResumeTasks = false
    }
    
    // MARK: ImageRequestEquating
    
    func isEqual(_ lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return manager.isLoadEquivalent(lhs, to: rhs) ?? false
    }
}
