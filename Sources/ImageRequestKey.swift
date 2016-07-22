// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Makes it possible to use ImageRequest as a key.
public final class ImageRequestKey: Hashable {
    private let request: ImageRequest
    private weak var equator: ImageRequestEquating?
    
    init(request: ImageRequest, equator: ImageRequestEquating?) {
        self.request = request
        self.equator = equator
    }

    /// Returns hash from the request's URL.
    public var hashValue: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }
}

/// Compares two keys for equivalence.
public func ==(lhs: ImageRequestKey, rhs: ImageRequestKey) -> Bool {
    if let equator = lhs.equator, lhs.equator === rhs.equator {
        return equator.isEqual(lhs.request, to: rhs.request)
    }
    return false
}

protocol ImageRequestEquating: class {
    func isEqual(_ lhs: ImageRequest, to rhs: ImageRequest) -> Bool
}

class ImageRequestEquator: ImageRequestEquating {
    private var closure: (ImageRequest, to: ImageRequest) -> Bool
    init(closure: (ImageRequest, to: ImageRequest) -> Bool) {
        self.closure = closure
    }
    func isEqual(_ lhs: ImageRequest, to rhs: ImageRequest) -> Bool {
        return closure(lhs, to: rhs)
    }
}
