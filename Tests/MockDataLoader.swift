//
//  MockDataLoader.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import Foundation
import Nuke

class MockDataLoader: DataLoading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")
    
    var enabled = true {
        didSet {
            queue.isSuspended = !enabled
        }
    }
    var createdTaskCount = 0
    private let queue = OperationQueue()

    func loadData(for request: URLRequest, progress: DataLoadingProgress? = nil, completion: DataLoadingCompletion) -> Cancellable {
        let task = MockDataTask()
        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)
        task.cancellation = { _ in
            NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
        }
        
        queue.addOperation {
            progress?(completed: 50, total: 100)
            progress?(completed: 100, total: 100)
            let bundle = Bundle(for: MockDataLoader.self)
            let URL = bundle.urlForResource("Image", withExtension: "jpg")
            let data = try! Data(contentsOf: URL!)
            DispatchQueue.main.async {
                completion(result: .success((data, URLResponse())))
            }
        }
        
        createdTaskCount += 1
        return task
    }
}

class MockDataTask: Cancellable {
    var cancellation: ((MockDataTask) -> Void)?
    func cancel() {
        cancellation?(self)
    }
}

