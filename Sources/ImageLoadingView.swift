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
    public var handler: ((view: ImageLoadingView, response: ImageResponse, options: ImageViewLoadingOptions, isFromMemoryCache: Bool) -> Void)? = nil
    
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
    func nk_setImageWith(_ request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask?
    
    /// Gets called when the task that is currently associated with the view completes.
    func nk_handle(_ response: ImageResponse, options: ImageViewLoadingOptions, isFromMemoryCache: Bool)
}

public extension ImageLoadingView {
    /// Loads and displays an image for the given URL. Cancels previously started requests.
    public func nk_setImageWith(_ URL: Foundation.URL) -> ImageTask? {
        return nk_setImageWith(ImageRequest(URL: URL))
    }
    
    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImageWith(_ request: ImageRequest) -> ImageTask? {
        return nk_setImageWith(request, options: ImageViewLoadingOptions())
    }
}


// MARK: - ImageDisplayingView

/// View that can display images.
public protocol ImageDisplayingView: class {
    /// Displays a given image.
    func nk_displayImage(_ image: Image?)

}


// MARK: - Default ImageLoadingView Implementation

/// Default ImageLoadingView implementation.
public extension ImageLoadingView {

    /// Cancels current image task.
    public func nk_cancelLoading() {
        nk_imageLoadingController.cancelLoading()
    }

    /// Loads and displays an image for the given request. Cancels previously started requests.
    public func nk_setImageWith(_ request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask? {
        return nk_imageLoadingController.setImageWith(request, options: options)
    }

    /// Returns current task.
    public var nk_imageTask: ImageTask? {
        return nk_imageLoadingController.imageTask
    }
    
    /// Returns image loading controller associated with the view.
    public var nk_imageLoadingController: ImageViewLoadingController {
        if let loader = objc_getAssociatedObject(self, &AssociatedKeys.LoadingController) as? ImageViewLoadingController {
            return loader
        }
        let loader = ImageViewLoadingController { [weak self] in
            self?.nk_handle($0, options: $1, isFromMemoryCache: $2)
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
    public func nk_handle(_ response: ImageResponse, options: ImageViewLoadingOptions, isFromMemoryCache: Bool) {
        if let handler = options.handler {
            handler(view: self, response: response, options: options, isFromMemoryCache: isFromMemoryCache)
            return
        }
        switch response {
        case let .success(image):
            nk_displayImage(image)
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
        public func nk_displayImage(_ image: Image?) {
            self.image = image
        }
    }
#endif

#if os(OSX)
    extension NSImageView: ImageDisplayingView, ImageLoadingView {
        /// Displays a given image.
        public func nk_displayImage(image: Image?) {
            self.image = image
        }
    }
#endif


// MARK: - ImageViewLoadingController

public typealias ImageViewLoadingHandler = (response: ImageResponse, options: ImageViewLoadingOptions, isFromMemoryCache: Bool) -> Void

/// Manages execution of image tasks for image loading view.
public class ImageViewLoadingController {
    /// Current task.
    public var imageTask: ImageTask?
    
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
    public func setImageWith(_ request: ImageRequest, options: ImageViewLoadingOptions) -> ImageTask? {
        cancelLoading()
        
        if request.memoryCachePolicy != .reloadIgnoringCachedImage {
            if let image = manager.imageForRequest(request) {
                self.handler(response: ImageResponse.success(image), options: options, isFromMemoryCache: true)
                return nil
            }
        }
        
        let task = manager.taskWith(request) { [weak self] task, response in
            if task == self?.imageTask {
                self?.handler(response: response, options: options, isFromMemoryCache: false)
            }
        }
        imageTask = task
        task.resume()
        return task
    }
}
