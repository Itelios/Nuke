//
//  MockImageCache.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 04/10/15.
//  Copyright (c) 2016 Alexander Grebenyuk. All rights reserved.
//

import Foundation
import Nuke

class MockImageCache: ImageCaching {
    var enabled = true
    var images = [URL: Image]()
    init() {}

    func image(for request: ImageRequest) -> Image? {
        return enabled ? images[request.urlRequest.url!] : nil
    }
    
    func setImage(_ image: Image, for request: ImageRequest) {
        if enabled {
            images[request.urlRequest.url!] = image
        }
    }
    
    func removeImage(for request: ImageRequest) {
        if enabled {
            images[request.urlRequest.url!] = nil
        }
    }
    
    func clear() {
        images.removeAll()
    }
}
