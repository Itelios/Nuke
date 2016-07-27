// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Provides basic networking using NSURLSession.
public final class DataLoader: Loading {
    public typealias ObjectType = (Data, URLResponse)

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
    public func loadImage(for request: Request, progress: LoadingProgress?, completion: (result: Result<ObjectType, AnyError>) -> Void) -> Cancellable {
        let task = session.dataTask(with: request.urlRequest)
        sessionDelegate.register(task: task, progress: progress, completion: completion)
        task.resume()
        return task
    }
}

extension URLSessionTask: Cancellable {}

private final class SessionDelegate: NSObject, URLSessionDataDelegate {
    typealias Progress = (completed: Int64, total: Int64) -> Void
    typealias Completion = (result: Result<(Data, URLResponse), AnyError>) -> Void

    var handlers = [URLSessionTask: Handler]()
    let queue = DispatchQueue(label: "\(domain).SessionDelegate")

    func register(task: URLSessionTask, progress: Progress?, completion: Completion) {
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
        let progress: Progress?
        let completion: Completion

        init(progress: Progress?, completion: Completion) {
            self.progress = progress
            self.completion = completion
        }
    }
}

