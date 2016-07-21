// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - DataLoading

public typealias DataLoadingProgress = (completed: Int64, total: Int64) -> Void
public typealias DataLoadingCompletion = (result: Result<(Data, URLResponse), NSError>) -> Void

/// Performs loading of image data.
public protocol DataLoading {
    /// Creates task with a given request. Task is resumed by the object calling the method.
    func loadData(for urlRequest: URLRequest, progress: DataLoadingProgress, completion: DataLoadingCompletion) -> URLSessionTask
}


// MARK: - DataLoader

/// Provides basic networking using NSURLSession.
public class DataLoader: NSObject, URLSessionDataDelegate, DataLoading {
    public private(set) var session: URLSession!
    private var handlers = [URLSessionTask: Handler]()
    private var lock = RecursiveLock()

    /// Initialzies data loader by creating a session with a given session configuration.
    public init(configuration: URLSessionConfiguration) {
        super.init()
        self.session = Foundation.URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Initializes the receiver with a default NSURLSession configuration and NSURLCache with memory capacity set to 0, disk capacity set to 200 Mb.
    public convenience override init() {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(memoryCapacity: 0, diskCapacity: (200 * 1024 * 1024), diskPath: "com.github.kean.nuke-cache")
        self.init(configuration: conf)
    }
    
    // MARK: DataLoading

    /// Creates task for the given request.
    public func loadData(for urlRequest: URLRequest, progress: DataLoadingProgress, completion: DataLoadingCompletion) -> URLSessionTask {
        let task = self.task(with: urlRequest)
        lock.lock()
        handlers[task] = Handler(progress: progress, completion: completion)
        lock.unlock()
        return task
    }
    
    /// Factory method for creating session tasks for given image requests.
    public func task(with urlRequest: URLRequest) -> URLSessionTask {
        return session.dataTask(with: urlRequest)
    }
    
    // MARK: NSURLSessionDataDelegate
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if let handler = handlers[dataTask] {
            handler.data.append(data)
            handler.progress(completed: dataTask.countOfBytesReceived, total: dataTask.countOfBytesExpectedToReceive)
        }
        lock.unlock()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: NSError?) {
        lock.lock()
        if let handler = handlers[task] {
            if let response = task.response {
                let val = (handler.data, response)
                handler.completion(result: .success(val))
            } else {
                handler.completion(result: .failure(error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)))
            }
            handlers[task] = nil
        }
        lock.unlock()
    }
    
    // MARK: Handler
    
    private class Handler {
        var data = Data()
        let progress: DataLoadingProgress
        let completion: DataLoadingCompletion
        
        init(progress: DataLoadingProgress, completion: DataLoadingCompletion) {
            self.progress = progress
            self.completion = completion
        }
    }
}
