// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// On-disk storage for data.
///
/// Nuke doesn't provide a built-in implementation of this protocol.
/// However, it's very easy to implement one in an extension of some
/// existing library (like DFCache).
public protocol DataCaching {
    /// Returns response for the given request.
    func response(for request: URLRequest) -> CachedURLResponse?

    /// Stores response for the given request.
    func setResponse(_ response: CachedURLResponse, for request: URLRequest)
}
