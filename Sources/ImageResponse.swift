// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents image response.
public enum ImageResponse {
    /// Task completed successfully.
    case success(Image)

    /// Task either failed or was cancelled. See ImageManagerErrorDomain for more info.
    case failure(ErrorProtocol)
}

/// Convenience methods to access associated values.
public extension ImageResponse {
    /// Returns image if the response was successful.
    public var image: Image? {
        switch self {
        case .success(let image): return image
        case .failure(_): return nil
        }
    }

    /// Returns error if the response failed.
    public var error: ErrorProtocol? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }

    /// Returns true if the response was successful.
    public var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
}
