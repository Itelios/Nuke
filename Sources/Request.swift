// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Encapsulates image request parameters.
public struct Request {
    public var urlRequest: URLRequest

    /// Filters to be applied to the image.
    public var processors = [AnyProcessor]()
    
    public mutating func add<T: Processing>(processor: T) {
        processors.append(AnyProcessor(processor))
    }
    
    /// Allows users to pass some custom info alongside the request.
    public var userInfo: Any?
    
    /// Initializes `Request` with a URL.
    public init(url: URL) {
        self.urlRequest = URLRequest(url: url)
    }
    
    /// Initializes `Request` with a URL request.
    public init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }
    
    internal var processor: ProcessorComposition? {
        return processors.isEmpty ? nil : ProcessorComposition(processors: processors)
    }
}

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
