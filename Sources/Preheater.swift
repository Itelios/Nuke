// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public class Preheater {
    
    /// Default value is 3.
    public var maxConcurrentTaskCount = 3

    private let manager: Manager
    private let equator: RequestEquating
    private var map = [RequestKey: Task]()
    private var tasks = [Task]() // we need ordered tasks, map's not enough
    private var needsToResumeTasks = false
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Preheater.Queue", attributes: DispatchQueueAttributes.serial)

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public init(manager: Manager, equator: RequestEquating = RequestLoadingEquator()) {
        self.manager = manager
        self.equator = equator
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsResumeTasks), name: Task.DidUpdateState, object: nil)
    }

    /**
     Prepares images for the given requests for later use.

     When you call this method, Manager starts to load and cache images for the given requests. Manager caches images with the exact target size, content mode, and filters. At any time afterward, you can create tasks with equivalent requests.
     */
    public func startPreheating(for requests: [Request]) {
        queue.async {
            requests.forEach {
                self.startPreheating(for: $0)
            }
            self.setNeedsResumeTasks()
        }
    }
    
    private func startPreheating(for request: Request) {
        let key = RequestKey(request: request, equator: equator)
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
    public func stopPreheating(for requests: [Request]) {
        queue.async {
            requests.forEach {
                self.map[RequestKey(request: $0, equator: self.equator)]?.cancel()
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
