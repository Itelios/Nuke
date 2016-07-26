// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    public typealias View = NSView
    public typealias ImageView = NSImageView
#else
    import UIKit
    public typealias View = UIView
    public typealias ImageView = UIImageView
#endif

/// View that supports image loading and it managed by `Manager`.
public protocol ManagedView: class {
    /// Cancels current task.
    func nk_cancelLoading()
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    func nk_setImage(with request: Request, options: Manager.Options)
    
    /// Called when current tasks is completed.
    func nk_handle(response: Task.Response, isFromMemoryCache: Bool)
}

/// Default ManagedView implementation.
public extension ManagedView {

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

    /// Returns image loading context associated with the view.
    public var nk_context: ManagedViewContext {
        if let ctx = objc_getAssociatedObject(self, &contextAK) as? ManagedViewContext {
            return ctx
        }
        let ctx = ManagedViewContext()
        ctx.handler = { [weak self] in
            self?.nk_handle(response: $0, isFromMemoryCache: $1)
        }
        objc_setAssociatedObject(self, &contextAK, ctx, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return ctx
    }
}

private var contextAK = "nk_context"


/// Default implementation for image task completion handler.
public extension ManagedView where Self: ImageDisplaying, Self: View {
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
                let layer: CALayer? = self.layer // Make compiler happy on OSX
                layer?.add(animation, forKey: "imageTransition")
            }
        case .failure(_): return
        }
    }
}

// MARK: - ManagedViewContext

/// Task execution context of the `ManagedView`.
public final class ManagedViewContext {
    public typealias Handler = (response: Task.Response, isFromMemoryCache: Bool) -> Void

    /// Current task.
    public private(set) var task: Task?

    /// Handler that gets called each time current task completes.
    private var handler: Handler?

    /// `Manager.shared` by default.
    public var manager: Manager = Manager.shared

    deinit {
        cancel()
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Initializes `ManagedViewContext`.
    public init() {}
}

// MARK: - ImageDisplaying

/// View that can display images.
public protocol ImageDisplaying: class {
    /// Displays a given image.
    func nk_display(_ image: Image?)
}

extension ImageView: ImageDisplaying, ManagedView {
    /// Displays a given image.
    public func nk_display(_ image: Image?) {
        self.image = image
    }
}
