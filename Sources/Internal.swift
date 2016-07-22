// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

// MARK: OperationQueue Extension

extension OperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}

// MARK: Operation

/// Concurrent operation with closures.
class Operation: Foundation.Operation {
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
            cancellation = starter() {
                self.isExecuting = false
                self.isFinished = true
            }
        }
    }
    
    override func cancel() {
        lock.sync {
            if !self.isCancelled && !self.isFinished {
                super.cancel()
                cancellation?()
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
