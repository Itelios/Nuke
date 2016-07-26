// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    public typealias ImageView = NSImageView
#else
    import UIKit
    public typealias ImageView = UIImageView
#endif

/// By adopting `ResponseHandling` protocol the class automatically gets a bunch
/// of methods for loading images from the `ResponseHandling` extension.
/// In general you implement this protocol in your views.
public protocol ResponseHandling: class {
    /// Called when the current task is completed.
    func nk_handle(response: Manager.Response, isFromMemoryCache: Bool)
}

/// Extends `ResponseHandling` with a bunch of methods for loading images.
public extension ResponseHandling {
    /// Cancels the current task. The completion handler doesn't get called.
    public func nk_cancelLoading() {
        nk_context.cancel()
    }
    
    /// Loads an image for the given URL and displays it when finished.
    /// For more info see `nk_setImage(with:options:)` method.
    public func nk_setImage(with url: URL) {
        nk_setImage(with: Request(url: url))
    }

    /// Loads an image for the given request and displays it when finished.
    /// Cancels previously started requests.
    ///
    /// If the image is stored in the `Manager`'s memory cache, the image is
    /// displayed immediately. Otherwise the image is loaded using the `Manager`
    /// and is displayed when finished.
    /// - parameter options: `Manager.Options()` by default.
    public func nk_setImage(with request: Request, options: Manager.Options = Manager.Options()) {
        let ctx = nk_context
        
        ctx.cancel()
        
        if let image = ctx.manager.image(for: request, options: options) {
            ctx.handler?(response: .success(image), isFromMemoryCache: true)
        } else {
            ctx.task = ctx.manager.task(with: request) { [weak ctx] task, response in
                guard task == ctx?.task else { return }
                ctx?.handler?(response: response, isFromMemoryCache: false)
            }
            ctx.task?.resume()
        }
    }

    /// Returns the context associated with the receiver.
    public var nk_context: ViewContext {
        if let ctx = objc_getAssociatedObject(self, &contextAK) as? ViewContext {
            return ctx
        }
        let ctx = ViewContext()
        ctx.handler = { [weak self] in
            self?.nk_handle(response: $0, isFromMemoryCache: $1)
        }
        objc_setAssociatedObject(self, &contextAK, ctx, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return ctx
    }
}

private var contextAK = "nk_context"

/// Default implementation of `ResponseHandling` protocol for `ImageView`.
extension ImageView: ResponseHandling {
    /// Simply displays an image on success and runs `opacity` transition if
    /// the response was not from the memory cache.
    ///
    /// To customize response handling you should either override this method
    /// in the subclass, or set a `handler` on the context (`nk_context`).
    public func nk_handle(response: Manager.Response, isFromMemoryCache: Bool) {
        switch response {
        case let .success(image):
            self.image = image
            if !isFromMemoryCache {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.duration = 0.25
                animation.fromValue = 0
                animation.toValue = 1
                let layer: CALayer? = self.layer // Make compiler happy on OSX
                layer?.add(animation, forKey: "imageTransition")
            }
        case .failure(_): return
        }
    }
}

/// Execution context used by `ResponseHandling` extension.
public final class ViewContext {
    public typealias Handler = (response: Manager.Response, isFromMemoryCache: Bool) -> Void
    
    /// Current task.
    public private(set) var task: Task?
    
    /// Called when the current task is completed.
    public var handler: Handler?
    
    /// `Manager.shared` by default.
    public var manager: Manager = Manager.shared

    /// Cancels current task.
    deinit {
        cancel()
    }

    /// Cancels the current task. The completion handler doesn't get called.
    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Initializes `ViewContext`.
    public init() {}
}
