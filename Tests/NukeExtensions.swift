// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension Nuke.Loader.Error {
    var loadingError: AnyError? {
        switch self {
        case let .loadingFailed(err): return err
        default: return nil
        }
    }
    
    var isDecodingError: Bool {
        switch self {
        case .decodingFailed: return true
        default: return false
        }
    }
    
    var isProcessingError: Bool {
        switch self {
        case .processingFailed: return true
        default: return false
        }
    }
}

extension Nuke.Manager.Error {
    var isCancelled: Bool {
        switch self {
        case .cancelled: return true
        default: return false
        }
    }

    var loadingError: AnyError? {
        switch self {
        case let .loadingFailed(err): return err
        default: return nil
        }
    }
}
