// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/**
 On-disk storage for data.
 
 Nuke doesn't provide a built-in implementation of this protocol. However, it's very easy to implement one in an extension of some existing library, for example, DFCache (see Example project for more info).
*/
public protocol DataCaching {
    /// Stores data for the given request.
    func setData(_ data: Data, response: URLResponse, for request: ImageRequest)
    
    /// Returns data for the given request.
    func data(for request: ImageRequest) -> Data?
}
