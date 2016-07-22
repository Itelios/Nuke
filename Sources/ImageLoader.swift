// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

public typealias ImageLoadingResult = Result<Image, Error>
public typealias ImageLoadingProgress = (progress: Progress) -> Void
public typealias ImageLoadingCompletion = (result: ImageLoadingResult) -> Void

/// Performs loading of images.
public protocol ImageLoading: class {
    /// Loads image for the given request.
    func loadImage(for request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion) -> Cancellable
}

// MARK: - ImageLoader

/**
Performs loading of images for the image tasks.

This class uses multiple dependencies provided in its configuration. Image data is loaded using an object conforming to `DataLoading` protocol. Image data is decoded via `DataDecoding` protocol. Decoded images are processed by objects conforming to `ImageProcessing` protocols.

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
    
    public enum Error: ErrorProtocol {
        case loadingFailed(NSError)
        case decodingFailed
        case processingFailed
    }

    public let dataCache: DataCaching?
    public let dataLoader: DataLoading
    public let dataDecoder: DataDecoding
    public let queues: ImageLoader.Queues

    private let queue = DispatchQueue(label: "ImageLoader.Queue", attributes: DispatchQueueAttributes.serial)
    
    /// Initializes image loader with a configuration.
    public init(
        dataLoader: DataLoading,
        dataDecoder: DataDecoding = DataDecoder(),
        dataCache: DataCaching? = nil,
        queues: ImageLoader.Queues = ImageLoader.Queues())
    {
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.dataDecoder = dataDecoder
        self.queues = queues
    }

    /// Resumes loading for the image task.
    public func loadImage(for request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion) -> Cancellable {
        let task = Task(request: request, progress: progress, completion: completion, cancellation: { [weak self] in
            self?.cancel($0)
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

    private func loadData(for task: Task, dataCache: DataCaching) {
        enterState(task, state: .dataCacheLookup(BlockOperation() {
            let data = dataCache.data(for: task.request)
            self.then(for: task) {
                if let data = data {
                    self.decode(data: data, task: task)
                } else {
                    self.loadData(for: task)
                }
            }
        }))
    }

    private func loadData(for task: Task) {
        enterState(task, state: .dataLoading(Operation() { fulfill in
            let dataTask = self.dataLoader.loadData(
                for: task.request.urlRequest,
                progress: { completed, total in
                    self.queue.async {
                        task.progress(progress: Progress(completed: completed, total: total))
                    }
                },
                completion: {
                    fulfill()
                    self.then(for: task, result: $0) { data, response in
                        self.store(data: data, response: response, for: task.request)
                        self.decode(data: data, response: response, task: task)
                    }
            })
            dataTask.resume()
            return {
                dataTask.cancel()
            }
        }))
    }
    
    private func store(data: Data, response: URLResponse, for request: ImageRequest) {
        if let cache = dataCache {
            queues.dataCaching.addOperation(BlockOperation() {
                cache.setData(data, response: response, for: request)
            })
        }
    }
    
    private func decode(data: Data, response: URLResponse? = nil, task: Task) {
        enterState(task, state: .dataDecoding(BlockOperation() {
            let image = self.dataDecoder.decode(data: data, response: response)
            let result = Result(value: image, error: Error.decodingFailed)
            self.then(for: task, result: result) { image in
                self.process(image, task: task)
            }
        }))
    }

    private func process(_ image: Image, task: Task) {
        if let processor = task.request.processor {
            process(image, task: task, processor: processor)
        } else {
            complete(task, result: .success(image))
        }
    }

    private func process(_ image: Image, task: Task, processor: ImageProcessing) {
        enterState(task, state: .processing(BlockOperation() {
            let result = Result(value: processor.process(image), error: Error.processingFailed)
            self.then(for: task, result: result) { image in
                self.complete(task, result: .success(image))
            }
        }))
    }

    private func complete(_ task: Task, result: ImageLoadingResult) {
        task.completion(result: result)
    }

    private func enterState(_ task: Task, state: Task.State) {
        switch state {
        case .dataCacheLookup(let op): queues.dataCaching.addOperation(op)
        case .dataLoading(let op): queues.dataLoading.addOperation(op)
        case .dataDecoding(let op): queues.dataLoading.addOperation(op)
        case .processing(let op): queues.processing.addOperation(op)
        }
        task.state = state
    }

    private func cancel(_ task: Task) {
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

    private func then(for task: Task, block: ((Void) -> Void)) {
        queue.async {
            if !task.cancelled {
                block() // execute only if task is still registered
            }
        }
    }
    
    private func then<V, E: ErrorProtocol>(for task: Task, result: Result<V, E>, block: ((V) -> Void)) {
        then(for: task) {
            switch result {
            case let .success(val): block(val)
            case let .failure(err): self.complete(task, result: .failure(Nuke.Error(err)))
            }
        }
    }
    
    // MARK: - Task
    
    private class Task: Cancellable {
        enum State {
            case dataCacheLookup(Foundation.Operation)
            case dataLoading(Foundation.Operation)
            case dataDecoding(Foundation.Operation)
            case processing(Foundation.Operation)
        }
        
        var request: ImageRequest
        let progress: ImageLoadingProgress
        let completion: ImageLoadingCompletion
        var cancellationHandler: (Task) -> Void
        var cancelled = false
        var state: State?
        
        init(request: ImageRequest, progress: ImageLoadingProgress, completion: ImageLoadingCompletion, cancellation: (Task) -> Void) {
            self.request = request
            self.progress = progress
            self.completion = completion
            self.cancellationHandler = cancellation
        }
        
        func cancel() {
            cancellationHandler(self)
        }
    }
}
