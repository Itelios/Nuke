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
    var images = [ImageRequestKey: Image]()
    init() {}

    func image(for key: ImageRequestKey) -> Image? {
        return enabled ? images[key] : nil
    }
    
    func setImage(_ image: Image, for key: ImageRequestKey) {
        if enabled {
            images[key] = image
        }
    }
    
    func removeImage(for key: ImageRequestKey) {
        if enabled {
            images[key] = nil
        }
    }
    
    func clear() {
        images.removeAll()
    }
}
