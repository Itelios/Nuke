// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public typealias LoadingProgress = (completed: Int64, total: Int64) -> Void
public typealias LoadingCompletion = (result: Result<Image, AnyError>) -> Void

/// Performs loading of images.
public protocol Loading: class {
    /// Loads an image for the given request.
    ///
    /// The implementation is not required to call the completion handler
    /// when the load gets cancelled.
    func loadImage(for request: Request, progress: LoadingProgress?, completion: LoadingCompletion) -> Cancellable
}

/// Performs loading of images.
///
/// This class implements an image loading pipeline. First, data is loaded using
/// an object conforming to `DataLoading` protocol. Then data is decoded using
/// `DataDecoding` protocol. Decoded images are then processed by objects
/// conforming to `Processing` protocol which are provided by `Request`.
///
/// You can initialize `Loader` with `DataCaching` object to add data caching
/// into a pipeline. Custom data cache might be more performant than caching
/// provided by `URL Loading System` (if that's what is used for loading).
public class Loader: Loading {
    public enum Error: ErrorProtocol {
        case loadingFailed(NSError)
        case decodingFailed
        case processingFailed
    }

    public let dataCache: DataCaching?
    public let dataLoader: DataLoading
    public let dataDecoder: DataDecoding
    public let queues: Loader.Queues
    
    /// Queues which are used to execute a corresponding steps of the pipeline.
    public struct Queues {
        /// `maxConcurrentOperationCount` is 2 be default.
        public var dataCaching = OperationQueue(maxConcurrentOperations: 2)
        // Based on benchmark there is a ~2.3x increase in performance when
        // increasing `maxConcurrentOperationCount` to 2, but this factor
        // drops sharply after that (tested with DFCache and FileManager).
        
        /// `maxConcurrentOperationCount` is 8 be default.
        public var dataLoading = OperationQueue(maxConcurrentOperations: 8)

        /// `maxConcurrentOperationCount` is 1 be default.
        public var dataDecoding = OperationQueue(maxConcurrentOperations: 1)
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `ImageDataDecoder` that locks globally while decoding.
        
        /// `maxConcurrentOperationCount` is 2 be default.
        public var processing = OperationQueue(maxConcurrentOperations: 2)
    }
    
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Loader.Queue", attributes: DispatchQueueAttributes.serial)
    
    /// Initializes `Loader` instance with the given data loader, decoder and
    /// cache. You could also provide loader with you own set of queues.
    /// - parameter dataCache: `nil` by default.
    /// - parameter queues: `Loader.Queues()` by default.
    public init(
        dataLoader: DataLoading,
        dataDecoder: DataDecoding,
        dataCache: DataCaching? = nil,
        queues: Loader.Queues = Loader.Queues()) {
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.dataDecoder = dataDecoder
        self.queues = queues
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(for request: Request, progress: LoadingProgress? = nil, completion: LoadingCompletion) -> Cancellable {
        let task = Task(request, progress, completion, cancellation: {
            self.cancel($0)
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
        enterState(task, state: .dataCaching(BlockOperation() {
            let response = dataCache.response(for: task.request.urlRequest)
            self.then(for: task) {
                if let response = response {
                    self.decode(data: response.data, response: response.response, for: task)
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
                        task.progress?(completed: completed, total: total)
                    }
                },
                completion: {
                    fulfill()
                    self.then(for: task, result: $0) { data, response in
                        self.store(data: data, response: response, for: task)
                        self.decode(data: data, response: response, for: task)
                    }
            })
            return {
                fulfill()
                dataTask.cancel()
            }
        }))
    }
    
    private func store(data: Data, response: URLResponse, for task: Task) {
        if let cache = dataCache {
            queues.dataCaching.addOperation(BlockOperation() {
                cache.setResponse(CachedURLResponse(response: response, data: data), for: task.request.urlRequest)
            })
        }
    }
    
    private func decode(data: Data, response: URLResponse, for task: Task) {
        enterState(task, state: .dataDecoding(BlockOperation() {
            let image = self.dataDecoder.decode(data: data, response: response)
            let result = Result(image, error: Error.decodingFailed)
            self.then(for: task, result: result) { image in
                self.process(image, for: task)
            }
        }))
    }

    private func process(_ image: Image, for task: Task) {
        if let processor = task.request.processor {
            enterState(task, state: .processing(BlockOperation() {
                let result = Result(processor.process(image), error: Error.processingFailed)
                self.then(for: task, result: result) { image in
                    self.complete(task, result: .success(image))
                }
            }))
        } else {
            complete(task, result: .success(image))
        }
    }

    private func complete(_ task: Task, result: Result<Image, AnyError>) {
        task.completion(result: result)
    }

    private func enterState(_ task: Task, state: Task.State) {
        switch state {
        case .dataCaching(let op): queues.dataCaching.addOperation(op)
        case .dataLoading(let op): queues.dataLoading.addOperation(op)
        case .dataDecoding(let op): queues.dataDecoding.addOperation(op)
        case .processing(let op): queues.processing.addOperation(op)
        }
        task.state = state
    }

    private func cancel(_ task: Task) {
        queue.async {
            if let state = task.state {
                switch state {
                case .dataCaching(let op): op.cancel()
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
                block()
            }
        }
    }
    
    private func then<V, E: ErrorProtocol>(for task: Task, result: Result<V, E>, block: ((V) -> Void)) {
        then(for: task) {
            switch result {
            case let .success(val): block(val)
            case let .failure(err): self.complete(task, result: .failure(AnyError(err)))
            }
        }
    }
    
    private class Task: Cancellable {
        enum State {
            case dataCaching(Foundation.Operation)
            case dataLoading(Foundation.Operation)
            case dataDecoding(Foundation.Operation)
            case processing(Foundation.Operation)
        }
        
        var request: Request
        let progress: LoadingProgress?
        let completion: LoadingCompletion
        var cancellation: (Task) -> Void
        var cancelled = false
        var state: State?
        
        init(_ request: Request, _ progress: LoadingProgress?, _ completion: LoadingCompletion, cancellation: (Task) -> Void) {
            self.request = request
            self.progress = progress
            self.completion = completion
            self.cancellation = cancellation
        }
        
        func cancel() {
            cancellation(self)
        }
    }
}
