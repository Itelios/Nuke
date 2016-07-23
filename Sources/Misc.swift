// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: ImageRequestKey

/// Makes it possible to use ImageRequest as a key.
final class ImageRequestKey: Hashable {
    private let request: ImageRequest
    private let equator: ImageRequestEquating
    
    init(request: ImageRequest, equator: ImageRequestEquating) {
        self.request = request
        self.equator = equator
    }
    
    /// Returns hash from the request's URL.
    var hashValue: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }
}

/// Compares two keys for equivalence.
func ==(lhs: ImageRequestKey, rhs: ImageRequestKey) -> Bool {
    return lhs.equator.isEqual(lhs.request, to: rhs.request)
}

// MARK: OperationQueue Extension

extension OperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}

// MARK: Operation

final class Operation: Foundation.Operation {
    override var isExecuting : Bool {
        get { return _isExecuting }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    private var _isExecuting = false
    
    override var isFinished : Bool {
        get { return _isFinished }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    private var _isFinished = false
    
    typealias Cancellation = (Void) -> Void
    typealias Fulfill = (Void) -> Void
    
    let starter: (fulfill: Fulfill) -> Cancellation?
    private var cancellation: Cancellation?
    private let lock = RecursiveLock()
    
    init(starter: (fulfill: Fulfill) -> Cancellation?) {
        self.starter = starter
    }
    
    override func start() {
        lock.sync {
            isExecuting = true
            if isCancelled {
                finish()
            } else {
                cancellation = starter() { [weak self] in
                    self?.finish()
                }
            }
        }
    }
    
    private func finish() {
        lock.sync {
            isExecuting = false
            isFinished = true
            cancellation = nil
        }
    }
    
    override func cancel() {
        lock.sync {
            if !isCancelled {
                super.cancel()
                cancellation?() // user should call fulfill
            }
        }
    }
}

// MARK: Locking

extension Locking {
    func sync(_ closure: @noescape (Void) -> Void) {
        _ = synced(closure)
    }
    
    func synced<T>(_ closure: @noescape (Void) -> T) -> T {
        lock()
        let result = closure()
        unlock()
        return result
    }
}
