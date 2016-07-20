// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/**
 On-disk storage for image data.
 
 Nuke doesn't provide a built-in implementation of this protocol. However, it's very easy to implement it in an extension of some existing library, for example, DFCache (see Example project for more info).
*/
public protocol ImageDataCaching {
    /// Stores data for the given request.
    func set(data: Data, response: URLResponse, for request: ImageRequest)
    
    /// Returns data for the given request.
    func data(for request: ImageRequest) -> Data?
}
