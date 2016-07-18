// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - ImageLoading

/// Performs loading of images.
public protocol ImageLoading: class {
    /// Manager that controls image loading.
    weak var manager: ImageLoadingManager? { get set }
    
    /// Resumes loading for the given task.
    func resumeLoadingFor(task: ImageTask)

    /// Cancels loading for the given task.
    func cancelLoadingFor(task: ImageTask)
    
    /// Compares requests for equivalence with regard to caching output images. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
    func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /// Invalidates the receiver. This method gets called by the manager when it is invalidated.
    func invalidate()
    
    /// Clears the receiver's cache storage (if any).
    func removeAllCachedImages()
}

// MARK: - ImageLoadingDelegate

/// Manages image loading.
public protocol ImageLoadingManager: class {
    /// Sent periodically to notify the manager of the task progress.
    func loader(loader: ImageLoading, task: ImageTask, didUpdateProgress progress: ImageTaskProgress)
    
    /// Sent when loading for the task is completed.
    func loader(loader: ImageLoading, task: ImageTask, didCompleteWithImage image: Image?, error: ErrorType?, userInfo: Any?)
}

// MARK: - ImageLoaderConfiguration

/// Configuration options for an ImageLoader.
public struct ImageLoaderConfiguration {
    /// Performs loading of image data.
    public var dataLoader: ImageDataLoading

    /// Decodes data into image objects.
    public var decoder: ImageDecoding

    /// Stores image data into a disk cache.
    public var cache: ImageDiskCaching?
    
    /// Image caching queue (both read and write). Default queue has a maximum concurrent operation count 2.
    public var cachingQueue = NSOperationQueue(maxConcurrentOperationCount: 2) // based on benchmark: there is a ~2.3x increase in performance when increasing maxConcurrentOperationCount from 1 to 2, but this factor drops sharply right after that
    
    /// Data loading queue.
    public var dataLoadingQueue = NSOperationQueue(maxConcurrentOperationCount: 8)
    
    /// Image processing queue. Default queue has a maximum concurrent operation count 2.
    public var processingQueue = NSOperationQueue(maxConcurrentOperationCount: 2)
    
    /**
     Initializes configuration with data loader and image decoder.
     
     - parameter dataLoader: Image data loader.
     - parameter decoder: Image decoder. Default `ImageDecoder` instance is created if the parameter is omitted.
     */
    public init(dataLoader: ImageDataLoading, decoder: ImageDecoding = ImageDecoder(), cache: ImageDiskCaching? = nil) {
        self.dataLoader = dataLoader
        self.decoder = decoder
        self.cache = cache
    }
}

// MARK: - ImageLoaderDelegate

/// Image loader customization endpoints.
public protocol ImageLoaderDelegate {
    /// Compares requests for equivalence with regard to caching output images. This method is used for memory caching, in most cases there is no need for filtering out the dynamic part of the request (is there is any).
    func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool
    
    /// Returns processor for the given request and image.
    func loader(loader: ImageLoader, processorFor: ImageRequest, image: Image) -> ImageProcessing?
}

/// Default implementation of ImageLoaderDelegate.
public extension ImageLoaderDelegate {
    /// Constructs image decompressor based on the request's target size and content mode (if decompression is allowed). Combined the decompressor with the processor provided in the request.
    public func processorFor(request: ImageRequest, image: Image) -> ImageProcessing? {
        var processors = [ImageProcessing]()
        if request.shouldDecompressImage, let decompressor = decompressorFor(request) {
            processors.append(decompressor)
        }
        if let processor = request.processor {
            processors.append(processor)
        }
        return processors.isEmpty ? nil : ImageProcessorComposition(processors: processors)
    }

    /// Returns decompressor for the given request.
    public func decompressorFor(request: ImageRequest) -> ImageProcessing? {
        #if os(OSX)
            return nil
        #else
            return ImageDecompressor(targetSize: request.targetSize, contentMode: request.contentMode)
        #endif
    }
}

/**
 Default implementation of ImageLoaderDelegate.
 
 The default implementation is provided in a class which allows methods to be overridden.
 */
public class ImageLoaderDefaultDelegate: ImageLoaderDelegate {
    /// Initializes the delegate.
    public init() {}

    /// Compares request `URL`s, decompression parameters (`shouldDecompressImage`, `targetSize` and `contentMode`), and processors.
    public func loader(loader: ImageLoader, isCacheEquivalent lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return lhs.URLRequest.URL == rhs.URLRequest.URL &&
            lhs.shouldDecompressImage == rhs.shouldDecompressImage &&
            lhs.targetSize == rhs.targetSize &&
            lhs.contentMode == rhs.contentMode &&
            isEquivalent(lhs.processor, rhs: rhs.processor)
    }
    
    private func isEquivalent(lhs: ImageProcessing?, rhs: ImageProcessing?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l.isEquivalent(r)
        case (nil, nil): return true
        default: return false
        }
    }
    
    /// Constructs image decompressor based on the request's target size and content mode (if decompression is allowed). Combined the decompressor with the processor provided in the request.
    public func loader(loader: ImageLoader, processorFor request: ImageRequest, image: Image) -> ImageProcessing? {
        return processorFor(request, image: image)
    }
}

// MARK: - ImageLoader

/**
Performs loading of images for the image tasks.

This class uses multiple dependencies provided in its configuration. Image data is loaded using an object conforming to `ImageDataLoading` protocol. Image data is decoded via `ImageDecoding` protocol. Decoded images are processed by objects conforming to `ImageProcessing` protocols.

- Provides transparent loading, decoding and processing with a single completion signal
- Reuses session tasks for equivalent request
*/
public class ImageLoader: ImageLoading {
    /// Manages image loading.
    public weak var manager: ImageLoadingManager?

    /// The configuration that the receiver was initialized with.
    public let configuration: ImageLoaderConfiguration
    private var conf: ImageLoaderConfiguration { return configuration }
    
    /// Delegate that the receiver was initialized with. Image loader holds a strong reference to its delegate!
    public let delegate: ImageLoaderDelegate
    
    private var loadStates = [ImageTask : ImageLoadState]()
    private let queue = dispatch_queue_create("ImageLoader.Queue", DISPATCH_QUEUE_SERIAL)
    
    /**
     Initializes image loader with a configuration and a delegate.

     - parameter delegate: Instance of `ImageLoaderDefaultDelegate` created if the parameter is omitted. Image loader holds a strong reference to its delegate!
     */
    public init(configuration: ImageLoaderConfiguration, delegate: ImageLoaderDelegate = ImageLoaderDefaultDelegate()) {
        self.configuration = configuration
        self.delegate = delegate
    }

    /// Resumes loading for the image task.
    public func resumeLoadingFor(task: ImageTask) {
        queue.async {
            if let cache = self.conf.cache {
                // FIXME: Use better approach for managing tasks
                self.loadStates[task] = .CacheLookup(self.conf.cachingQueue.addBlock { [weak self] in
                    let data = cache.dataFor(task)
                    self?.queue.async {
                        if let data = data {
                            self?.processData(data, task: task)
                        } else {
                            guard self?.loadStates[task] != nil else { /* no longer registered */ return }
                            self?.loadDataFor(task)
                        }
                    }
                })
            } else {
                self.loadDataFor(task)
            }
        }
    }

    private func loadDataFor(task: ImageTask) {
        let operation = DataOperation<DataOperationResult>() { fulfill in
            let dataTask = self.conf.dataLoader.taskWith(
                task.request,
                progress: { [weak self] dataTask, completed, total in
                    self?.dataTask(dataTask, imageTask: task, didUpdateProgress: ImageTaskProgress(completed: completed, total: total))
                },
                completion: { [weak self] dataTask, data, response, error in
                    self?.queue.async {
                        fulfill((data, response, error))
                        self?.dataTask(dataTask, imageTask: task, didCompleteWithData: data, response: response, error: error)
                    }
                })
            #if !os(OSX)
                if let priority = task.request.priority {
                    dataTask.priority = priority
                }
            #endif
            return dataTask
        }
        conf.dataLoadingQueue.addOperation(operation)
        loadStates[task] = .Loading(operation)
    }

    private func dataTask(dataTask: NSURLSessionTask, imageTask: ImageTask, didUpdateProgress progress: ImageTaskProgress) {
        queue.async {
            self.manager?.loader(self, task: imageTask, didUpdateProgress: progress)
        }
    }
    
    private func dataTask(dataTask: NSURLSessionTask, imageTask: ImageTask,didCompleteWithData data: NSData?, response: NSURLResponse?, error: ErrorType?) {
        if let data = data where error == nil {
            if let response = response, cache = conf.cache {
                conf.cachingQueue.addBlock {
                    cache.setData(data, response: response, forTask: imageTask)
                }
            }
            processData(data, response: response, task: imageTask)
        } else {
            complete(imageTask, image: nil, error: error)
        }
    }

    private func processData(data: NSData, response: NSURLResponse? = nil, task: ImageTask) {
        guard loadStates[task] != nil else { return }
        loadStates[task] = .Processing(conf.processingQueue.addBlock {
            guard let image = self.conf.decoder.decode(data, response: response) else {
                self.complete(task, image: nil, error: errorWithCode(.DecodingFailed))
                return
            }
            if let processor = self.delegate.loader(self, processorFor:task.request, image: image) {
                let image = processor.process(image)
                self.complete(task, image: image, error: (image == nil ? errorWithCode(.ProcessingFailed) : nil))
            } else { // processing not required
                self.complete(task, image: image, error: nil)
            }
        })
    }
    
    private func complete(task: ImageTask, image: Image?, error: ErrorType?) {
        queue.async {
            self.manager?.loader(self, task: task, didCompleteWithImage: image, error: error, userInfo: nil)
            self.loadStates[task] = nil
        }
    }

    /// Cancels loading for the task if there are no other outstanding executing tasks registered with the underlying data task.
    public func cancelLoadingFor(task: ImageTask) {
        queue.async {
            if let state = self.loadStates[task] {
                switch state {
                case .CacheLookup(let operation): operation.cancel()
                case .Loading(let operation): operation.cancel()
                case .Processing(let operation): operation.cancel()
                }
                self.loadStates[task] = nil // No longer registered
            }
        }
    }

    /// Comapres two requests using ImageLoaderDelegate for equivalence in regards to memory caching.
    public func isCacheEquivalent(lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return delegate.loader(self, isCacheEquivalent: lhs, to: rhs)
    }

    /// Signals the data loader to invalidate.
    public func invalidate() {
        conf.dataLoader.invalidate()
    }

    /// Signals data loader and cache (if not nil) to remove all cached images.
    public func removeAllCachedImages() {
        conf.cache?.removeAllCachedImages()
        conf.dataLoader.removeAllCachedImages()
    }
}

private enum ImageLoadState {
    case CacheLookup(NSOperation)
    case Loading(NSOperation)
    case Processing(NSOperation)
}


// TEMP:
typealias DataOperationResult = (NSData?, NSURLResponse?, ErrorType?)

/// Wraps data task in a concurrent NSOperation subclass
private class DataOperation<T>: Operation {
    var task: NSURLSessionTask?
    let starter: (T -> Void) -> NSURLSessionTask
    var result: T?
    private let lock = NSRecursiveLock()
    
    init(starter: (fulfill: (T) -> Void) -> NSURLSessionTask) {
        self.starter = starter
    }
    
    private override func start() {
        lock.lock()
        executing = true
        task = starter() { result in
            self.result = result
            self.executing = false
            self.finished = true
        }
        task?.resume()
        lock.unlock()
    }
    
    private override func cancel() {
        lock.lock()
        if !self.cancelled {
            super.cancel()
            task?.cancel()
        }
        lock.unlock()
    }
}
