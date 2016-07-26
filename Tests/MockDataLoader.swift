// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockDataLoader: DataLoading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")
    
    var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse), AnyError>]()
    let queue = OperationQueue()

    func loadData(for request: URLRequest, progress: DataLoadingProgress? = nil, completion: DataLoadingCompletion) -> Cancellable {
        let task = Task()
        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)
        task.cancellation = { _ in
            NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
        }
        
        createdTaskCount += 1

        queue.addOperation {
            progress?(completed: 50, total: 100)
            progress?(completed: 100, total: 100)
            let bundle = Bundle(for: MockDataLoader.self)
            let URL = bundle.urlForResource("Image", withExtension: "jpg")
            let data = try! Data(contentsOf: URL!)
            DispatchQueue.main.async {
                if let result = self.results[request.url!] {
                    completion(result: result)
                } else {
                    completion(result: .success((data, URLResponse())))
                }
            }
        }
        
        return task
    }

private class Task: Cancellable {
    var cancellation: ((Task) -> Void)?
    func cancel() {
        cancellation?(self)
    }
}
}
