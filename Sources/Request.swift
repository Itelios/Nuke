// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

// MARK: - Request

/// Encapsulates image request parameters.
public struct Request {
    /// Defines constants that can be used to modify the way Manager interacts with the memory cache.
    public enum MemoryCachePolicy {
        /// Return memory cached image corresponding the request. If there is no existing image in the memory cache, the image manager continues with the request.
        case returnCachedObjectElseLoad
        
        /// Reload using ignoring memory cached objects. Doesn't affect on-disk caching.
        case reloadIgnoringCachedObject
    }
    
    /// The URL request.
    public var urlRequest: URLRequest

    /// Specifies whether loaded object should be stored into memory cache. Default value is true.
    public var memoryCacheStorageAllowed = true
    
    /// The request memory cache policy. Default value is .returnCachedObjectElseLoad.
    public var memoryCachePolicy = MemoryCachePolicy.returnCachedObjectElseLoad

    /// Filters to be applied to the image.
    public var processors = [AnyProcessor]()
    
    public mutating func add<T: Processing>(processor: T) {
        processors.append(AnyProcessor(processor))
    }

    /// Allows users to pass some custom info alongside the request.
    public var userInfo: Any?
    
    /// Initializes request with a URL.
    public init(url: URL) {
        self.urlRequest = URLRequest(url: url)
    }
    
    /// Initializes request with a URL request.
    public init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }
}

extension Request {
    var processor: ProcessorComposition? {
        return processors.isEmpty ? nil : ProcessorComposition(processors: processors)
    }
}

// MARK: - RequestEquating

public protocol RequestEquating {
    func isEqual(_ a: Request, to b: Request) -> Bool
}

public struct RequestLoadingEquator: RequestEquating {
    public init() {}
    
    public func isEqual(_ a: Request, to b: Request) -> Bool {
        return isLoadEquivalent(a.urlRequest, to: b.urlRequest) && a.processor == b.processor
    }
    
    private func isLoadEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        return a.url == b.url &&
            a.cachePolicy == b.cachePolicy &&
            a.timeoutInterval == b.timeoutInterval &&
            a.networkServiceType == b.networkServiceType &&
            a.allowsCellularAccess == b.allowsCellularAccess
    }
}

public struct RequestCachingEquator: RequestEquating {
    public init() {}
    
    public func isEqual(_ a: Request, to b: Request) -> Bool {
        return a.urlRequest.url == b.urlRequest.url && a.processor == b.processor
    }
}
