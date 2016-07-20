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


// MARK: Error Handling

func errorWithCode(code: ImageManagerErrorCode) -> NSError {
    func reason() -> String {
        switch code {
        case .Unknown: return "The image manager encountered an error that it cannot interpret."
        case .Cancelled: return "The image task was cancelled."
        case .DecodingFailed: return "The image manager failed to decode image data."
        case .ProcessingFailed: return "The image manager failed to process image data."
        }
    }
    return NSError(domain: ImageManagerErrorDomain, code: code.rawValue, userInfo: [NSLocalizedFailureReasonErrorKey: reason()])
}


// MARK: GCD

extension dispatch_queue_t {
    func async(block: (Void -> Void)) { dispatch_async(self, block) }
}


// MARK: NSOperationQueue Extensions

extension NSOperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}


// MARK: Operation

class Operation: NSOperation {
    override var executing : Bool {
        get { return _executing }
        set {
            willChangeValueForKey("isExecuting")
            _executing = newValue
            didChangeValueForKey("isExecuting")
        }
    }
    private var _executing = false
    
    override var finished : Bool {
        get { return _finished }
        set {
            willChangeValueForKey("isFinished")
            _finished = newValue
            didChangeValueForKey("isFinished")
        }
    }
    private var _finished = false
}

/// Wraps data task in a concurrent NSOperation subclass
class DataOperation: Operation {
    var task: NSURLSessionTask?
    let starter: (Void -> Void) -> NSURLSessionTask
    private let lock = NSRecursiveLock()

    init(starter: (fulfill: (Void) -> Void) -> NSURLSessionTask) {
        self.starter = starter
    }

    override func start() {
        lock.lock()
        executing = true
        task = starter() {
            self.executing = false
            self.finished = true
        }
        task?.resume()
        lock.unlock()
    }

    override func cancel() {
        lock.lock()
        if !self.cancelled {
            super.cancel()
            task?.cancel()
        }
        lock.unlock()
    }
}
