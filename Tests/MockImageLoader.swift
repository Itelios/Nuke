// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let image: Image = {
    let bundle = Bundle(for: MockImageLoader.self)
    let URL = bundle.urlForResource("Image", withExtension: "jpg")
    let data = try! Data(contentsOf: URL!)
    return Nuke.ImageDataDecoder().decode(data: data, response: URLResponse())!
}()

class MockImageLoader: Loading {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockLoader.DidCancelTask")
    
    var createdTaskCount = 0
    let queue = OperationQueue()
    var results = [URL: Result<Image, AnyError>]()

    func loadImage(for request: Request, progress: LoadingProgress? = nil, completion: LoadingCompletion) -> Cancellable {
        let task = MockTask()
        NotificationCenter.default.post(name: MockImageLoader.DidStartTask, object: self)
        task.cancellation = { _ in
            NotificationCenter.default.post(name: MockImageLoader.DidCancelTask, object: self)
        }
        
        createdTaskCount += 1
        
        queue.addOperation {
            progress?(completed: 50, total: 100)
            progress?(completed: 100, total: 100)
            DispatchQueue.main.async {
                if let result = self.results[request.urlRequest.url!] {
                    completion(result: result)
                } else {
                    completion(result: .success(image))
                }
            }
        }
        
        return task
    }
}

private class MockTask: Cancellable {
    var cancellation: ((MockTask) -> Void)?
    func cancel() {
        cancellation?(self)
    }
}
