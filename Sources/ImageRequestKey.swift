// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Makes it possible to use ImageRequest as a key in dictionaries.
public final class ImageRequestKey: NSObject {
    /// Request that the receiver was initailized with.
    public let request: ImageRequest
    
    private let isEqual: (ImageRequestKey, to: ImageRequestKey) -> Bool
    
    /// Initializes the receiver with a given request and the closure that compares two keys for equivalence.
    public init(request: ImageRequest, isEqual: (ImageRequestKey, to: ImageRequestKey) -> Bool) {
        self.request = request
        self.isEqual = isEqual
    }

    /// Returns hash from the NSURL from image request.
    public override var hash: Int {
        return request.urlRequest.url?.hashValue ?? 0
    }

    /// Compares two keys for equivalence if the belong to the same owner.
    public override func isEqual(_ other: AnyObject?) -> Bool {
        guard let other = other as? ImageRequestKey else {
            return false
        }
        return self.isEqual(self, to: other)
    }
}
