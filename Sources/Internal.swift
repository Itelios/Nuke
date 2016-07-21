// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    /// Alias for NSImage
    public typealias Image = NSImage
#else
    import UIKit
    /// Alias for UIImage
    public typealias Image = UIImage
#endif

// MARK: Foundation.OperationQueue Extensions

extension OperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}

// MARK: Operation

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
}

/// Wraps data task in a concurrent Foundation.Operation subclass
class DataOperation: Operation {
    var task: URLSessionTask?
    let starter: ((Void) -> Void) -> URLSessionTask
    private let lock = RecursiveLock()

    init(starter: (fulfill: (Void) -> Void) -> URLSessionTask) {
        self.starter = starter
    }

    override func start() {
        lock.lock()
        isExecuting = true
        task = starter() {
            self.isExecuting = false
            self.isFinished = true
        }
        task?.resume()
        lock.unlock()
    }

    override func cancel() {
        lock.lock()
        if !self.isCancelled {
            super.cancel()
            task?.cancel()
        }
        lock.unlock()
    }
}
