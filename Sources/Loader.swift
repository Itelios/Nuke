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
/// `Loader` implements an image loading pipeline. First, data is loaded using
/// an object conforming to `DataLoading` protocol. Then data is decoded using
/// `DataDecoding` protocol. Decoded images are then processed by objects
/// conforming to `Processing` protocol which are provided by the `Request`.
///
/// You can initialize `Loader` with `DataCaching` object to add data caching
/// into the pipeline. Custom data cache might be more performant than caching
/// provided by `URL Loading System` (if that's what is used for loading).
public class Loader: Loading {
    public enum Error: ErrorProtocol {
        case loadingFailed(AnyError)
        case decodingFailed
        case processingFailed
    }
    
    public let cache: DataCaching?
    public let loader: DataLoading
    public let decoder: DataDecoding
    public let queues: Loader.Queues
    
    /// Queues which are used to execute a corresponding steps of the pipeline.
    public struct Queues {
        /// `maxConcurrentOperationCount` is 2 be default.
        public var caching = OperationQueue(maxConcurrentOperationCount: 2)
        // Based on benchmark there is a ~2.3x increase in performance when
        // increasing `maxConcurrentOperationCount` to 2, but this factor
        // drops sharply after that (tested with DFCache and FileManager).
        
        /// `maxConcurrentOperationCount` is 8 be default.
        public var loading = OperationQueue(maxConcurrentOperationCount: 8)

        /// `maxConcurrentOperationCount` is 1 be default.
        public var decoding = OperationQueue(maxConcurrentOperationCount: 1)
        // There is no reason to increase `maxConcurrentOperationCount` for
        // built-in `DataDecoder` that locks globally while decoding.

        /// `maxConcurrentOperationCount` is 2 be default.
        public var processing = OperationQueue(maxConcurrentOperationCount: 2)
    }

    /// Initializes `Loader` instance with the given data loader, decoder and
    /// cache. You could also provide loader with you own set of queues.
    /// - parameter dataCache: `nil` by default.
    /// - parameter queues: `Queues()` by default.
    public init(loader: DataLoading, decoder: DataDecoding, cache: DataCaching? = nil, queues: Queues = Queues()) {
        self.loader = loader
        self.cache = cache
        self.decoder = decoder
        self.queues = queues
    }

    /// Loads an image for the given request using image loading pipeline.
    public func loadImage(for request: Request, progress: LoadingProgress? = nil, completion: LoadingCompletion) -> Cancellable {
        return Pipeline(self, request, progress, completion)
    }
}

/// Implements image loading pipeline.
private class Pipeline: Cancellable {
    let ctx: Loader
    let request: Request
    let progress: LoadingProgress?
    let completion: LoadingCompletion
    var cancelled = false
    var subtask: Cancellable?
    let queue = DispatchQueue(label: "\(domain).Pipeline")
    
    /// Starts loading immediately after initialization.
    init(_ loader: Loader, _ request: Request, _ progress: LoadingProgress?, _ completion: LoadingCompletion) {
        self.ctx = loader
        self.request = request
        self.progress = progress
        self.completion = completion
        queue.sync {
            if let cache = ctx.cache {
                loadData(cache: cache)
            } else {
                loadData()
            }
        }
    }
    
    func loadData(cache: DataCaching) {
        subtask = ctx.queues.caching.add(BlockOperation() {
            let response = cache.response(for: self.request.urlRequest)
            self.then {
                if let response = response {
                    self.decode(data: response.data, response: response.response)
                } else {
                    self.loadData()
                }
            }
        })
    }
    
    func loadData() {
        subtask = ctx.queues.loading.add(Operation() { fulfill in
            return self.ctx.loader.loadData(
                for: self.request.urlRequest,
                progress: { completed, total in
                    self.progress?(completed: completed, total: total)
                },
                completion: {
                    fulfill()
                    let result = Result(from: $0) { Loader.Error.loadingFailed($0) }
                    self.then(with: result) { data, response in
                        self.store(data: data, response: response)
                        self.decode(data: data, response: response)
                    }
                })
        })
    }
    
    func store(data: Data, response: URLResponse) {
        if let cache = ctx.cache {
            ctx.queues.caching.addOperation(BlockOperation() {
                cache.setResponse(CachedURLResponse(response: response, data: data), for: self.request.urlRequest)
            })
        }
    }
    
    func decode(data: Data, response: URLResponse) {
        subtask = ctx.queues.decoding.add(BlockOperation() {
            let image = self.ctx.decoder.decode(data: data, response: response)
            self.then(with: Result(image, error: Loader.Error.decodingFailed)) {
                self.process($0)
            }
        })
    }
    
    func process(_ image: Image) {
        if let processor = request.processor {
            subtask = ctx.queues.processing.add(BlockOperation() {
                let image = processor.process(image)
                self.then(with: Result(image, error: Loader.Error.processingFailed)) {
                    self.complete(with: .success($0))
                }
            })
        } else {
            complete(with: .success(image))
        }
    }
    
    func complete(with result: Result<Image, AnyError>) {
        completion(result: result)
        subtask = nil // break retain cycle
    }
    
    func cancel() {
        queue.sync {
            cancelled = true
            subtask?.cancel()
            subtask = nil
        }
    }
    
    func then(_ closure: @noescape (Void) -> Void) {
        queue.sync {
            if !cancelled {
                closure()
            }
        }
    }
    
    func then<V>(with result: Result<V, Loader.Error>, closure: @noescape (V) -> Void) {
        then {
            switch result {
            case let .success(val): closure(val)
            case let .failure(err): complete(with: .failure(AnyError(err)))
            }
        }
    }
}
