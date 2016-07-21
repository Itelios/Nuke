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

// MARK: - ImageViewLoadingOptions

/// Options for image loading.
public struct ImageViewLoadingOptions {
    /// Custom animations to run when the image is displayed. Default value is nil.
    public var animations: ((ImageLoadingView) -> Void)? = nil
    
    /// If true the loaded image is displayed with animation. Default value is true.
    public var animated = true
    
    /// Custom handler to run when the task completes. Overrides the default completion handler. Default value is nil.
    public var handler: ((view: ImageLoadingView, result: ImageManager.Task.ResultType, options: ImageViewLoadingOptions, isFromMemoryCache: Bool) -> Void)? = nil
    
    /// Default value is nil.
    public var userInfo: Any? = nil

    /// Initializes the receiver.
    public init() {}
}


// MARK: - ImageLoadingView

/// View that supports image loading.
public protocol ImageLoadingView: class {
    /// Cancels the task currently associated with the view.
    func nk_cancelLoading()
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    func nk_setImage(with request: ImageRequest, options: ImageViewLoadingOptions) -> ImageManager.Task?
    
    /// Gets called when the task that is currently associated with the view completes.
    func nk_handle(result: ImageManager.Task.ResultType, options: ImageViewLoadingOptions, isFromMemoryCache: Bool)
}

public extension ImageLoadingView {
    /// Loads and displays an image for the given URL. Cancels previously started requests.
    public func nk_setImage(url: URL) -> ImageManager.Task? {
        return nk_setImage(with: ImageRequest(url: url))
    }
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImage(with request: ImageRequest) -> ImageManager.Task? {
        return nk_setImage(with: request, options: ImageViewLoadingOptions())
    }
}


// MARK: - ImageDisplayingView

/// View that can display images.
public protocol ImageDisplayingView: class {
    /// Displays a given image.
    func nk_display(_ image: Image?)

}


// MARK: - Default ImageLoadingView Implementation

/// Default ImageLoadingView implementation.
public extension ImageLoadingView {

    /// Cancels current image task.
    public func nk_cancelLoading() {
        nk_imageLoadingController.cancelLoading()
    }

    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImage(with request: ImageRequest, options: ImageViewLoadingOptions) -> ImageManager.Task? {
        return nk_imageLoadingController.setImage(with: request, options: options)
    }

    /// Returns current task.
    public var nk_imageTask: ImageManager.Task? {
        return nk_imageLoadingController.imageTask
    }
    
    /// Returns image loading controller associated with the view.
    public var nk_imageLoadingController: ImageViewLoadingController {
        if let loader = objc_getAssociatedObject(self, &AssociatedKeys.LoadingController) as? ImageViewLoadingController {
            return loader
        }
        let loader = ImageViewLoadingController { [weak self] in
            self?.nk_handle(result: $0, options: $1, isFromMemoryCache: $2)
        }
        objc_setAssociatedObject(self, &AssociatedKeys.LoadingController, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return loader
    }
}

private struct AssociatedKeys {
    static var LoadingController = "nk_imageViewLoadingController"
}

/// Default implementation for image task completion handler.
public extension ImageLoadingView where Self: ImageDisplayingView, Self: View {
    
    /// Default implementation that displays the image and runs animations if necessary.
    public func nk_handle(result: ImageManager.Task.ResultType, options: ImageViewLoadingOptions, isFromMemoryCache: Bool) {
        if let handler = options.handler {
            handler(view: self, result: result, options: options, isFromMemoryCache: isFromMemoryCache)
            return
        }
        switch result {
        case let .ok(image):
            nk_display(image)
            if options.animated && !isFromMemoryCache {
                if let animations = options.animations {
                    animations(self) // User provided custom animations
                } else {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.duration = 0.25
                    animation.fromValue = 0
                    animation.toValue = 1
                    let layer: CALayer? = self.layer // Make compiler happy
                    layer?.add(animation, forKey: "imageTransition")
                }
            }
        default: return
        }
    }
}


// MARK: - ImageLoadingView Conformance

#if os(iOS) || os(tvOS)
    extension UIImageView: ImageDisplayingView, ImageLoadingView {
        /// Displays a given image.
        public func nk_display(_ image: Image?) {
            self.image = image
        }
    }
#endif

#if os(OSX)
    extension NSImageView: ImageDisplayingView, ImageLoadingView {
        /// Displays a given image.
        public func nk_display(_ image: Image?) {
            self.image = image
        }
    }
#endif


// MARK: - ImageViewLoadingController

public typealias ImageViewLoadingHandler = (result: ImageManager.Task.ResultType, options: ImageViewLoadingOptions, isFromMemoryCache: Bool) -> Void

/// Manages execution of image tasks for image loading view.
public class ImageViewLoadingController {
    /// Current task.
    public var imageTask: ImageManager.Task?
    
    /// Handler that gets called each time current task completes.
    public var handler: ImageViewLoadingHandler
    
    /// The image manager used for creating tasks. The shared manager is used by default.
    public var manager: ImageManager = ImageManager.shared
    
    deinit {
        cancelLoading()
    }
    
    /// Initializes the receiver with a given handler.
    public init(handler: ImageViewLoadingHandler) {
        self.handler = handler
    }
    
    /// Cancels current task.
    public func cancelLoading() {
        imageTask?.cancel()
        imageTask = nil
    }
    
    /// Creates a task, subscribes to it and resumes it.
    public func setImage(with request: ImageRequest, options: ImageViewLoadingOptions) -> ImageManager.Task? {
        cancelLoading()
        
        if request.memoryCachePolicy != .reloadIgnoringCachedImage {
            if let image = manager.image(for: request) {
                self.handler(result: .ok(image), options: options, isFromMemoryCache: true)
                return nil
            }
        }
        
        let task = manager.task(with: request) { [weak self] task, result in
            if task == self?.imageTask {
                self?.handler(result: result, options: options, isFromMemoryCache: false)
            }
        }
        imageTask = task
        task.resume()
        return task
    }
}
