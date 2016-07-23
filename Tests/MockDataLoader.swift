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
    static let DidStartDataTask = Notification.Name("com.github.kean.Nuke.Tests.DidStartDataTask")
    static let DidCancelDataTask = Notification.Name("com.github.kean.Nuke.Tests.DidCancelDataTask")
    
    var enabled = true {
        didSet {
            queue.isSuspended = !enabled
        }
    }
    var createdTaskCount = 0
    private let queue = OperationQueue()

    func loadData(for request: URLRequest, progress: DataLoadingProgress, completion: DataLoadingCompletion) -> Cancellable {
        let task = MockDataTask()
        NotificationCenter.default.post(name: MockDataLoader.DidStartDataTask, object: self)
        task.cancellation = { _ in
            NotificationCenter.default.post(name: MockDataLoader.DidCancelDataTask, object: self)
        }
        
        queue.addOperation {
            progress(completed: 50, total: 100)
            progress(completed: 100, total: 100)
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

