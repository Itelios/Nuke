// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

public typealias ImageLoadingProgress = (completed: Int64, total: Int64) -> Void
public typealias ImageLoadingCompletion = (Image?, ErrorType?) -> Void

/// Performs loading of images.
public protocol ImageLoading: class {
    /// Resumes loading for the given task.
    func loadImage(for request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion) -> Cancellable
}

// MARK: - ImageLoader

/**
Performs loading of images for the image tasks.

This class uses multiple dependencies provided in its configuration. Image data is loaded using an object conforming to `ImageDataLoading` protocol. Image data is decoded via `ImageDecoding` protocol. Decoded images are processed by objects conforming to `ImageProcessing` protocols.

- Provides transparent loading, decoding and processing with a single completion signal
*/
public class ImageLoader: ImageLoading {
    /// Queues on which to execute certain tasks.
    public struct Queues {
        /// Image caching queue (both read and write). Default queue has a maximum concurrent operation count 2.
        public var dataCaching = NSOperationQueue(maxConcurrentOperationCount: 2) // based on benchmark: there is a ~2.3x increase in performance when increasing maxConcurrentOperationCount from 1 to 2, but this factor drops sharply right after that

        /// Data loading queue. Default queue has a maximum concurrent operation count 8.
        public var dataLoading = NSOperationQueue(maxConcurrentOperationCount: 8)

        /// Image decoding queue. Default queue has a maximum concurrent operation count 1.
        public var dataDecoding = NSOperationQueue(maxConcurrentOperationCount: 1) // there is no reason to increase maxConcurrentOperationCount, because the built-in ImageDecoder locks while decoding data.

        /// Image processing queue. Default queue has a maximum concurrent operation count 2.
        public var processing = NSOperationQueue(maxConcurrentOperationCount: 2)
    }

    public let dataCache: ImageDiskCaching?
    public let dataLoader: ImageDataLoading
    public let dataDecoder: ImageDecoding
    public let queues: ImageLoader.Queues

    private let queue = dispatch_queue_create("ImageLoader.Queue", DISPATCH_QUEUE_SERIAL)
    
    /// Initializes image loader with a configuration.
    public init(
        dataLoader: ImageDataLoading = ImageDataLoader(),
        dataDecoder: ImageDecoding = ImageDecoder(),
        dataCache: ImageDiskCaching? = nil,
        queues: ImageLoader.Queues = ImageLoader.Queues())
    {
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.dataDecoder = dataDecoder
        self.queues = queues
    }

    /// Resumes loading for the image task.
    public func loadImage(for request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion) -> Cancellable {
        let task = ImageLoadTask(request: request, progress: progress, completion: completion, cancellation: { [weak self] in
            self?.cancelLoadingFor($0)
        })
        queue.async {
            if let dataCache = self.dataCache {
                self.loadDataFor(task, dataCache: dataCache)
            } else {
                self.loadDataFor(task)
            }
        }
        return task
    }

    private func loadDataFor(task: ImageLoadTask, dataCache: ImageDiskCaching) {
        enterState(task, state: .DataCacheLookup(NSBlockOperation() {
            self.then(for: task, result: dataCache.dataFor(task.request)) { data in
                if let data = data {
                    self.decode(data, task: task)
                } else {
                    self.loadDataFor(task)
                }
            }
        }))
    }

    private func loadDataFor(task: ImageLoadTask) {
        enterState(task, state: .DataLoading(DataOperation() { fulfill in
            let dataTask = self.dataLoader.loadData(
                for: task.request,
                progress: { [weak self] completed, total in
                    self?.queue.async {
                        task.progress(completed: completed, total: total)
                    }
                },
                completion: { [weak self] data, response, error in
                    fulfill()
                    let result = (data, response, error)
                    self?.storeResponse(result, for: task)
                    self?.then(for: task, result: result) { _ in
                        if let data = data where error == nil {
                            self?.decode(data, response: response, task: task)
                        } else {
                            self?.complete(task, error: error)
                        }
                    }
                })
            #if !os(OSX)
                if let priority = task.request.priority {
                    dataTask.priority = priority
                }
            #endif
            return dataTask
        }))
    }

    private func storeResponse(response: (NSData?, NSURLResponse?, ErrorType?), for task: ImageLoadTask) {
        if let data = response.0 where response.2 == nil {
            if let response = response.1, cache = dataCache {
                queues.dataCaching.addOperation(NSBlockOperation() {
                     cache.setData(data, response: response, for: task.request)
                })
            }
        }
    }
    
    private func decode(data: NSData, response: NSURLResponse? = nil, task: ImageLoadTask) {
        enterState(task, state: .DataDecoding(NSBlockOperation() {
            self.then(for: task, result: self.dataDecoder.decode(data, response: response)) { image in
                if let image = image {
                    self.process(image, task: task)
                } else {
                    self.complete(task, error: errorWithCode(.DecodingFailed))
                }
            }
        }))
    }

    private func process(image: Image, task: ImageLoadTask) {
        if let processor = task.request.processor {
            process(image, task: task, processor: processor)
        } else {
            complete(task, image: image)
        }
    }

    private func process(image: Image, task: ImageLoadTask, processor: ImageProcessing) {
        enterState(task, state: .Processing(NSBlockOperation() {
            self.then(for: task, result: processor.process(image)) { image in
                if let image = image {
                    self.complete(task, image: image)
                } else {
                    self.complete(task, error: errorWithCode(.ProcessingFailed))
                }
            }
        }))
    }

    private func complete(task: ImageLoadTask, image: Image? = nil, error: ErrorType? = nil) {
        task.completion(image, error)
    }

    private func enterState(task: ImageLoadTask, state: ImageLoadState) {
        switch state {
        case .DataCacheLookup(let op): queues.dataCaching.addOperation(op)
        case .DataLoading(let op): queues.dataLoading.addOperation(op)
        case .DataDecoding(let op): queues.dataLoading.addOperation(op)
        case .Processing(let op): queues.processing.addOperation(op)
        }
        task.state = state
    }

    /// Cancels loading for the task if there are no other outstanding executing tasks registered with the underlying data task.
    private func cancelLoadingFor(task: ImageLoadTask) {
        queue.async {
            if let state = task.state {
                switch state {
                case .DataCacheLookup(let op): op.cancel()
                case .DataLoading(let op): op.cancel()
                case .DataDecoding(let op): op.cancel()
                case .Processing(let op): op.cancel()
                }
            }
            task.cancelled = true
        }
    }

    private func then<T>(for task: ImageLoadTask, result: T, block: (T -> Void)) {
        queue.async {
            if !task.cancelled {
                block(result) // execute only if task is still registered
            }
        }
    }
}

private enum ImageLoadState {
    case DataCacheLookup(NSOperation)
    case DataLoading(NSOperation)
    case DataDecoding(NSOperation)
    case Processing(NSOperation)
}

// Implemented in a similar fation that ImageTaskInternal is
private class ImageLoadTask: Cancellable, Hashable {
    var request: ImageRequest
    let progress: ImageLoadingProgress
    let completion: ImageLoadingCompletion
    var cancellation: ImageLoadTask -> Void
    var cancelled = false
    var state: ImageLoadState?

    init(request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion, cancellation: (ImageLoadTask -> Void)) {
        self.request = request
        self.progress = progress
        self.completion = completion
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation(self)
    }

    var hashValue: Int {
        return unsafeAddressOf(self).hashValue
    }
}

/// Compares two image tasks by reference.
private func ==(lhs: ImageLoadTask, rhs: ImageLoadTask) -> Bool {
    return lhs === rhs
}
