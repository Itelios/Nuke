// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ImagePreheatController {
    public let manager: ImageManager

    /// Default value is 2.
    public var maxConcurrentTaskCount = 2

    private var tasks: [ImageRequestKey: ImageManager.Task] = [:]
    private var needsToResumeTasks = false
    private let queue = DispatchQueue(label: "ImagePreheatController.Queue", attributes: DispatchQueueAttributes.serial)

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
                let key = self.makePreheatKey($0)
                if self.tasks[key] == nil { // Don't create more than one task for the equivalent requests.
                    self.tasks[key] = self.manager.task(with: $0) { [weak self] _ in
                        self?.tasks[key] = nil
                    }
                }
            }
            self.setNeedsResumeTasks()
        }
    }

    private func makePreheatKey(_ request: ImageRequest) -> ImageRequestKey {
        return ImageRequestKey(request: request) { [weak self] lhs, rhs in
            return self?.manager.isLoadEquivalent(lhs.request, to: rhs.request) ?? false
        }
    }

    /// Stop preheating for the given requests. The request parameters should match the parameters used in startPreheatingImages method.
    public func stopPreheating(for requests: [ImageRequest]) {
        queue.async {
            requests.forEach {
                self.tasks[self.makePreheatKey($0)]?.cancel()
            }
        }
    }

    /// Stops all preheating tasks.
    public func stopPreheating() {
        queue.async {
            self.tasks.values.forEach {
                $0.cancel()
            }
        }
    }

    public func setNeedsResumeTasks() {
        if !needsToResumeTasks {
            needsToResumeTasks = true
            queue.after(when: DispatchTime.now() + Double(Int64((0.15 * Double(NSEC_PER_SEC)))) / Double(NSEC_PER_SEC)) { [weak self] in
                self?.resumeTasksIfNeeded()
            }
        }
    }

    private func resumeTasksIfNeeded() {
        needsToResumeTasks = false
        var executingTaskCount = manager.tasks.count
        // FIXME: Use sorted dictionary
        for task in (tasks.values.sorted { $0.identifier < $1.identifier }) {
            if executingTaskCount > maxConcurrentTaskCount {
                break
            }
            if task.state == .suspended {
                task.resume()
                executingTaskCount += 1
            }
        }
    }
}
