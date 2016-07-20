// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents image response.
public enum ImageResponse {
    /// Task completed successfully.
    case Success(Image)

    /// Task either failed or was cancelled. See ImageManagerErrorDomain for more info.
    case Failure(ErrorType)
}

/// Convenience methods to access associated values.
public extension ImageResponse {
    /// Returns image if the response was successful.
    public var image: Image? {
        switch self {
        case .Success(let image): return image
        case .Failure(_): return nil
        }
    }

    /// Returns error if the response failed.
    public var error: ErrorType? {
        switch self {
        case .Success: return nil
        case .Failure(let error): return error
        }
    }

    /// Returns true if the response was successful.
    public var isSuccess: Bool {
        switch self {
        case .Success: return true
        case .Failure: return false
        }
    }
}
