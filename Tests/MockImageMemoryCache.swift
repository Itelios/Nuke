//
//  MockImageMemoryCache.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 04/10/15.
//  Copyright (c) 2016 Alexander Grebenyuk. All rights reserved.
//

import Foundation
import Nuke

class MockImageMemoryCache: ImageMemoryCaching {
    var enabled = true
    var images = [ImageRequestKey: Image]()
    init() {}

    func imageForKey(key: ImageRequestKey) -> Image? {
        return self.enabled ? self.images[key] : nil
    }
    
    func setImage(image: Image, forKey key: ImageRequestKey) {
        if self.enabled {
            self.images[key] = image
        }
    }
    
    func removeImageForKey(key: ImageRequestKey) {
        if self.enabled {
            self.images[key] = nil
        }
    }
    
    func clear() {
        self.images.removeAll()
    }
}
