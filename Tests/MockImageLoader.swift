//
//  MockImageLoader.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 23/07/16.
//  Copyright © 2016 Alexander Grebenyuk. All rights reserved.
//

import Foundation
import Nuke

class MockImageLoader: ImageLoading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockImageLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockImageLoader.DidCancelTask")
    
    var createdTaskCount = 0
    let queue = OperationQueue()
    
    func loadImage(for request: ImageRequest, progress: ImageLoadingProgress? = nil, completion: ImageLoadingCompletion) -> Cancellable {
        let task = MockImageTask()
        NotificationCenter.default.post(name: MockImageLoader.DidStartTask, object: self)
        task.cancellation = { _ in
            NotificationCenter.default.post(name: MockImageLoader.DidCancelTask, object: self)
        }
        
        createdTaskCount += 1
        
        queue.addOperation {
            progress?(completed: 50, total: 100)
            progress?(completed: 100, total: 100)
            let bundle = Bundle(for: MockImageLoader.self)
            let URL = bundle.urlForResource("Image", withExtension: "jpg")
            let data = try! Data(contentsOf: URL!)
            let image = Nuke.DataDecoder().decode(data: data, response: URLResponse())!
            DispatchQueue.main.async {
                completion(result: .success(image))
            }
        }
        
        return task
    }
}

class MockImageTask: Cancellable {
    var cancellation: ((MockImageTask) -> Void)?
    func cancel() {
        cancellation?(self)
    }
}
