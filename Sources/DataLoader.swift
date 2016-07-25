// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public typealias DataLoadingProgress = (completed: Int64, total: Int64) -> Void
public typealias DataLoadingCompletion = (result: Result<(Data, URLResponse), AnyError>) -> Void

/// Performs loading of image data.
public protocol DataLoading {
    /// Creates a task with a given URL request.
    /// Task is resumed by the user that called the method.
    ///
    /// The implementation is not required to call the completion handler
    /// when the load gets cancelled.
    func loadData(for request: URLRequest, progress: DataLoadingProgress?, completion: DataLoadingCompletion) -> Cancellable
}

/// Provides basic networking using NSURLSession.
public final class DataLoader: DataLoading {
    public private(set) var session: URLSession
    private let sessionDelegate = SessionDelegate()

    /// Initialzies data loader with a given configuration.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration()) {
        self.session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    private static func defaultConfiguration() -> URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = URLCache(memoryCapacity: 0, diskCapacity: (200 * 1024 * 1024), diskPath: "\(domain).Cache")
        return conf
    }
    
    /// Creates task for the given request.
    public func loadData(for request: URLRequest, progress: DataLoadingProgress? = nil, completion: DataLoadingCompletion) -> Cancellable {
        let task = session.dataTask(with: request)
        sessionDelegate.register(task: task, progress: progress, completion: completion)
        task.resume()
        return task
    }

    private final class SessionDelegate: NSObject, URLSessionDataDelegate {
        var handlers = [URLSessionTask: Handler]()
        let queue = DispatchQueue(label: "\(domain).SessionDelegate", attributes: .serial)
        
        func register(task: URLSessionTask, progress: DataLoadingProgress?, completion: DataLoadingCompletion) {
            queue.sync {
                handlers[task] = Handler(progress: progress, completion: completion)
            }
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            queue.sync {
                if let handler = handlers[dataTask] {
                    handler.data.append(data)
                    handler.progress?(completed: dataTask.countOfBytesReceived, total: dataTask.countOfBytesExpectedToReceive)
                }
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: NSError?) {
            queue.sync {
                if let handler = handlers[task] {
                    if let response = task.response {
                        let val = (handler.data, response)
                        handler.completion(result: .success(val))
                    } else {
                        let error = error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
                        handler.completion(result: .failure(AnyError(error)))
                    }
                    handlers[task] = nil
                }
            }
        }
        
        final class Handler {
            var data = Data()
            let progress: DataLoadingProgress?
            let completion: DataLoadingCompletion
            
            init(progress: DataLoadingProgress?, completion: DataLoadingCompletion) {
                self.progress = progress
                self.completion = completion
            }
        }
    }
}

extension URLSessionTask: Cancellable {}
