// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

public typealias ImageLoadingProgress = (completed: Int64, total: Int64) -> Void
public typealias ImageLoadingCompletion = (Image?, ErrorProtocol?) -> Void

/// Performs loading of images.
public protocol ImageLoading: class {
    /// Loads image for the given request.
    func loadImage(for request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion) -> Cancellable
}

// MARK: - ImageLoader

/**
Performs loading of images for the image tasks.

This class uses multiple dependencies provided in its configuration. Image data is loaded using an object conforming to `ImageDataLoading` protocol. Image data is decoded via `ImageDataDecoding` protocol. Decoded images are processed by objects conforming to `ImageProcessing` protocols.

- Provides transparent loading, decoding and processing with a single completion signal
*/
public class ImageLoader: ImageLoading {
    /// Queues on which to execute certain tasks.
    public struct Queues {
        /// Image caching queue (both read and write). Default queue has a maximum concurrent operation count 2.
        public var dataCaching = OperationQueue(maxConcurrentOperationCount: 2) // based on benchmark: there is a ~2.3x increase in performance when increasing maxConcurrentOperationCount from 1 to 2, but this factor drops sharply right after that

        /// Data loading queue. Default queue has a maximum concurrent operation count 8.
        public var dataLoading = OperationQueue(maxConcurrentOperationCount: 8)

        /// Image decoding queue. Default queue has a maximum concurrent operation count 1.
        public var dataDecoding = OperationQueue(maxConcurrentOperationCount: 1) // there is no reason to increase maxConcurrentOperationCount, because the built-in ImageDecoder locks while decoding data.

        /// Image processing queue. Default queue has a maximum concurrent operation count 2.
        public var processing = OperationQueue(maxConcurrentOperationCount: 2)
    }

    public let dataCache: ImageDataCaching?
    public let dataLoader: ImageDataLoading
    public let dataDecoder: ImageDataDecoding
    public let queues: ImageLoader.Queues

    private let queue = DispatchQueue(label: "ImageLoader.Queue", attributes: DispatchQueueAttributes.serial)
    
    /// Initializes image loader with a configuration.
    public init(
        dataLoader: ImageDataLoading = ImageDataLoader(),
        dataDecoder: ImageDataDecoding = ImageDataDecoder(),
        dataCache: ImageDataCaching? = nil,
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
            self?.cancelLoading(for: $0)
        })
        queue.async {
            if let dataCache = self.dataCache {
                self.loadData(for: task, dataCache: dataCache)
            } else {
                self.loadData(for: task)
            }
        }
        return task
    }

    private func loadData(for task: ImageLoadTask, dataCache: ImageDataCaching) {
        enterState(task, state: .dataCacheLookup(BlockOperation() {
            self.then(for: task, result: dataCache.data(for: task.request)) { data in
                if let data = data {
                    self.decode(data: data, task: task)
                } else {
                    self.loadData(for: task)
                }
            }
        }))
    }

    private func loadData(for task: ImageLoadTask) {
        enterState(task, state: .dataLoading(DataOperation() { fulfill in
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
                    self?.store(response: result, for: task.request)
                    self?.then(for: task, result: result) { _ in
                        if let data = data, error == nil {
                            self?.decode(data: data, response: response, task: task)
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

    private func store(response: (Data?, URLResponse?, ErrorProtocol?), for request: ImageRequest) {
        if let data = response.0, response.2 == nil {
            if let response = response.1, let cache = dataCache {
                queues.dataCaching.addOperation(BlockOperation() {
                    cache.set(data: data, response: response, for: request)
                })
            }
        }
    }
    
    private func decode(data: Data, response: URLResponse? = nil, task: ImageLoadTask) {
        enterState(task, state: .dataDecoding(BlockOperation() {
            self.then(for: task, result: self.dataDecoder.decode(data: data, response: response)) { image in
                if let image = image {
                    self.process(image, task: task)
                } else {
                    self.complete(task, error: errorWithCode(.decodingFailed))
                }
            }
        }))
    }

    private func process(_ image: Image, task: ImageLoadTask) {
        if let processor = task.request.processor {
            process(image, task: task, processor: processor)
        } else {
            complete(task, image: image)
        }
    }

    private func process(_ image: Image, task: ImageLoadTask, processor: ImageProcessing) {
        enterState(task, state: .processing(BlockOperation() {
            self.then(for: task, result: processor.process(image)) { image in
                if let image = image {
                    self.complete(task, image: image)
                } else {
                    self.complete(task, error: errorWithCode(.processingFailed))
                }
            }
        }))
    }

    private func complete(_ task: ImageLoadTask, image: Image? = nil, error: ErrorProtocol? = nil) {
        task.completion(image, error)
    }

    private func enterState(_ task: ImageLoadTask, state: ImageLoadState) {
        switch state {
        case .dataCacheLookup(let op): queues.dataCaching.addOperation(op)
        case .dataLoading(let op): queues.dataLoading.addOperation(op)
        case .dataDecoding(let op): queues.dataLoading.addOperation(op)
        case .processing(let op): queues.processing.addOperation(op)
        }
        task.state = state
    }

    private func cancelLoading(for task: ImageLoadTask) {
        queue.async {
            if let state = task.state {
                switch state {
                case .dataCacheLookup(let op): op.cancel()
                case .dataLoading(let op): op.cancel()
                case .dataDecoding(let op): op.cancel()
                case .processing(let op): op.cancel()
                }
            }
            task.cancelled = true
        }
    }

    private func then<T>(for task: ImageLoadTask, result: T, block: ((T) -> Void)) {
        queue.async {
            if !task.cancelled {
                block(result) // execute only if task is still registered
            }
        }
    }
}

private enum ImageLoadState {
    case dataCacheLookup(Foundation.Operation)
    case dataLoading(Foundation.Operation)
    case dataDecoding(Foundation.Operation)
    case processing(Foundation.Operation)
}

// Implemented in a similar fation that ImageTaskInternal is
private class ImageLoadTask: Cancellable {
    var request: ImageRequest
    let progress: ImageLoadingProgress
    let completion: ImageLoadingCompletion
    var cancellation: (ImageLoadTask) -> Void
    var cancelled = false
    var state: ImageLoadState?

    init(request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion, cancellation: ((ImageLoadTask) -> Void)) {
        self.request = request
        self.progress = progress
        self.completion = completion
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation(self)
    }
}
