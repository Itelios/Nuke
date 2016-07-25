// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    public typealias View = NSView
#else
    import UIKit
    public typealias View = UIView
#endif

// MARK: - ImageLoadingView

/// View that supports image loading.
public protocol ImageLoadingView: class {
    /// Cancels the task currently associated with the view.
    func nk_cancelLoading()
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    func nk_setImage(with request: Request, options: Manager.Options)
    
    /// Gets called when the task that is currently associated with the view completes.
    func nk_handle(response: Task.Response, isFromMemoryCache: Bool)
}


// MARK: - ImageDisplaying

/// View that can display images.
public protocol ImageDisplaying: class {
    /// Displays a given image.
    func nk_display(_ image: Image?)
}


// MARK: - Default ImageLoadingView Implementation

/// Default ImageLoadingView implementation.
public extension ImageLoadingView {

    /// Cancels current image task.
    public func nk_cancelLoading() {
        nk_context.cancel()
    }
    
    /// Loads and displays an image for the given URL. Cancels previously started requests.
    public func nk_setImage(with url: URL) {
        nk_setImage(with: Request(url: url))
    }

    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImage(with request: Request, options: Manager.Options = Manager.Options()) {
        let ctx = nk_context
        
        ctx.cancel()
        
        if options.memoryCachePolicy != .reloadIgnoringCachedObject {
            if let image = ctx.manager.cache?.image(for: request) {
                ctx.handler(response: .success(image), isFromMemoryCache: true)
                return
            }
        }
        
        ctx.task = ctx.manager.task(with: request) { [weak ctx] task, response in
            if task == ctx?.task {
                ctx?.handler(response: response, isFromMemoryCache: false)
            }
        }
        ctx.task?.resume()
    }

    /// Returns current task.
    public var nk_task: Task? {
        return nk_context.task
    }
    
    /// Returns image loading controller associated with the view.
    public var nk_context: ImageViewLoadingContext {
        if let ctx = objc_getAssociatedObject(self, &contextAK) as? ImageViewLoadingContext {
            return ctx
        }
        let ctx = ImageViewLoadingContext { [weak self] in
            self?.nk_handle(response: $0, isFromMemoryCache: $1)
        }
        objc_setAssociatedObject(self, &contextAK, ctx, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return ctx
    }
}

private var contextAK = "nk_context"


/// Default implementation for image task completion handler.
public extension ImageLoadingView where Self: ImageDisplaying, Self: View {
    /// Default implementation that displays the image and runs animations if necessary.
    public func nk_handle(response: Task.Response, isFromMemoryCache: Bool) {
        switch response {
        case let .success(image):
            nk_display(image)
            if !isFromMemoryCache {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.duration = 0.25
                animation.fromValue = 0
                animation.toValue = 1
                let layer: CALayer? = self.layer // Make compiler happy
                layer?.add(animation, forKey: "imageTransition")
            }
        case .failure(_): return
        }
    }
}


// MARK: - ImageLoadingView Conformance

#if os(iOS) || os(tvOS)
    extension UIImageView: ImageDisplaying, ImageLoadingView {
        /// Displays a given image.
        public func nk_display(_ image: Image?) {
            self.image = image
        }
    }
#endif

#if os(OSX)
    extension NSImageView: ImageDisplaying, ImageLoadingView {
        /// Displays a given image.
        public func nk_display(_ image: Image?) {
            self.image = image
        }
    }
#endif


// MARK: - ImageViewLoadingContext

/// Manages execution context for image loading views.
public final class ImageViewLoadingContext {
    public typealias Handler = (response: Task.Response, isFromMemoryCache: Bool) -> Void
    
    /// Current task.
    public private(set) var task: Task?
    
    /// Handler that gets called each time current task completes.
    private var handler: Handler
    
    /// `Manager.shared` by default.
    public var manager: Manager = Manager.shared
    
    deinit {
        cancel()
    }
    
    public func cancel() {
        task?.cancel()
        task = nil
    }
    
    /// Initializes the receiver with a given handler.
    public init(handler: Handler) {
        self.handler = handler
    }
}
