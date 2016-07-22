//
//  DFCacheExtensions.swift
//  Nuke Demo
//
//  Created by Alexander Grebenyuk on 18/03/16.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import Foundation
import DFCache
import Nuke

extension DFDiskCache: Nuke.DataCaching {
    public func setResponse(_ response: CachedURLResponse, for request: URLRequest) {
        if let key = makeKey(for: request) {
            setData(NSKeyedArchiver.archivedData(withRootObject: response), forKey: key)
        }
    }

    public func response(for request: URLRequest) -> CachedURLResponse? {
        if let key = makeKey(for: request),
            let data = data(forKey: key) {
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? CachedURLResponse
        }
        return nil
    }

    private func makeKey(for request: URLRequest) -> String? {
        return request.url?.absoluteString
    }
}
