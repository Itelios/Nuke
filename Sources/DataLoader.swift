// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - DataLoading

public typealias DataLoadingProgress = (completed: Int64, total: Int64) -> Void
public typealias DataLoadingCompletion = (result: Result<(Data, URLResponse), NSError>) -> Void

/// Performs loading of image data.
public protocol DataLoading {
    /// Creates a task with a given URL request.
    /// Task is resumed by the user that called the method.
    func loadData(for urlRequest: URLRequest, progress: DataLoadingProgress, completion: DataLoadingCompletion) -> URLSessionTask
}


// MARK: - DataLoader

/// Provides basic networking using NSURLSession.
public class DataLoader: DataLoading {
    public private(set) var session: URLSession
    private let sessionDelegate = SessionDelegate()

    /// Initialzies data loader with a given configuration.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration()) {
        self.session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    private static func defaultConfiguration() -> URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(memoryCapacity: 0, diskCapacity: (200 * 1024 * 1024), diskPath: "com.github.kean.nuke-cache")
        return conf
    }
    
    // MARK: DataLoading

    /// Creates task for the given request.
    public func loadData(for urlRequest: URLRequest, progress: DataLoadingProgress, completion: DataLoadingCompletion) -> URLSessionTask {
        let task = session.dataTask(with: urlRequest)
        sessionDelegate.register(task: task, progress: progress, completion: completion)
        return task
    }

    // MARK: SessionDelegate
    
    private class SessionDelegate: NSObject, URLSessionDataDelegate {
        var handlers = [URLSessionTask: Handler]()
        var lock = RecursiveLock()
        
        func register(task: URLSessionTask, progress: DataLoadingProgress, completion: DataLoadingCompletion) {
            lock.sync {
                handlers[task] = Handler(progress: progress, completion: completion)
            }
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.sync {
                if let handler = handlers[dataTask] {
                    handler.data.append(data)
                    handler.progress(completed: dataTask.countOfBytesReceived, total: dataTask.countOfBytesExpectedToReceive)
                }
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: NSError?) {
            lock.sync {
                if let handler = handlers[task] {
                    if let response = task.response {
                        let val = (handler.data, response)
                        handler.completion(result: .success(val))
                    } else {
                        let error = error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
                        handler.completion(result: .failure(error))
                    }
                    handlers[task] = nil
                }
            }
        }
        
        class Handler {
            var data = Data()
            let progress: DataLoadingProgress
            let completion: DataLoadingCompletion
            
            init(progress: DataLoadingProgress, completion: DataLoadingCompletion) {
                self.progress = progress
                self.completion = completion
            }
        }
    }
}
