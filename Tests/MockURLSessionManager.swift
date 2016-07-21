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
    var enabled = true {
        didSet {
            self.queue.isSuspended = !enabled
        }
    }
    var createdTaskCount = 0
    private let queue = OperationQueue()

    func loadData(for request: ImageRequest, progress: DataLoadingProgress, completion: DataLoadingCompletion) -> URLSessionTask {
        self.queue.addOperation {
            progress(completed: 50, total: 100)
            progress(completed: 100, total: 100)
            let bundle = Bundle(for: MockDataLoader.self)
            let URL = bundle.urlForResource("Image", withExtension: "jpg")
            let data = try! Data(contentsOf: URL!)
            DispatchQueue.main.async {
                completion(result: Result(value: (data, URLResponse())))
            }
        }
        self.createdTaskCount += 1
        return MockURLSessionDataTask()
    }
}
