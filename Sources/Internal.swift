// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

internal let domain = "com.github.kean.Nuke"

// MARK: RequestKey

/// Makes it possible to use Request as a key.
internal struct RequestKey: Hashable {
    private let request: Request
    private let equator: RequestEquating
    
    init(_ request: Request, equator: RequestEquating) {
        self.request = request
        self.equator = equator
    }
    
    /// Returns hash from the request's URL.
    var hashValue: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }
}

/// Compares two keys for equivalence.
func ==(lhs: RequestKey, rhs: RequestKey) -> Bool {
    return lhs.equator.isEqual(lhs.request, to: rhs.request)
}

// MARK: Operations

internal extension OperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    func add(_ operation: Foundation.Operation) -> Foundation.Operation {
        addOperation(operation)
        return operation
    }
}

// MARK: Operation

internal final class Operation: Foundation.Operation {
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

    private let starter: (fulfill: (Void) -> Void) -> Cancellable?
    private var subtask: Cancellable?
    private let queue = DispatchQueue(label: "\(domain).Operation")
    
    init(starter: (fulfill: (Void) -> Void) -> Cancellable?) {
        self.starter = starter
    }
    
    override func start() {
        queue.sync {
            isExecuting = true
            if isCancelled {
                finish()
            } else {
                subtask = starter() { [weak self] in
                    _ = self?.queue.sync { self?.finish() }
                }
            }
        }
    }
    
    private func finish() {
        if !isFinished {
            isExecuting = false
            isFinished = true
            subtask = nil
        }
    }
    
    override func cancel() {
        queue.sync {
            if !isCancelled {
                super.cancel()
                if isExecuting {
                    subtask?.cancel()
                    finish()
                }
            }
        }
    }
}
