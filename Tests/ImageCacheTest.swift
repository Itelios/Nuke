//
//  ImageCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class ImageMockCacheTest: XCTestCase {
    var manager: ImageManager!
    var mocCache: MockImageCache!
    var mockSessionManager: MockDataLoader!
    
    override func setUp() {
        super.setUp()

        self.mocCache = MockImageCache()
        self.mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: self.mockSessionManager)
        self.manager = ImageManager(loader: loader, cache: self.mocCache)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatCacheWorks() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertEqual(self.mocCache.images.count, 0)
        XCTAssertNil(self.manager.image(for: request))

        self.expect { fulfill in
            self.manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mocCache.images.count, 1)
        XCTAssertNotNil(self.manager.image(for: request))
        
        self.mockSessionManager.enabled = false
        
        self.expect { fulfill in
            self.manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertEqual(self.mocCache.images.count, 0)
        XCTAssertNil(self.manager.image(for: request))
        
        self.manager.setImage(Image(), for: request)
        
        XCTAssertEqual(self.mocCache.images.count, 1)
        let response = self.manager.image(for: request)
        XCTAssertNotNil(response)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertEqual(self.mocCache.images.count, 0)
        XCTAssertNil(self.manager.image(for: request))
        
        self.manager.setImage(Image(), for: request)
        
        XCTAssertEqual(self.mocCache.images.count, 1)
        let response = self.manager.image(for: request)
        XCTAssertNotNil(response)
        
        self.manager.removeImage(for: request)
        XCTAssertEqual(self.mocCache.images.count, 0)
        XCTAssertNil(self.manager.image(for: request))
    }
    
    func testThatCacheStorageCanBeDisabled() {
        var request = ImageRequest(url: defaultURL)
        XCTAssertTrue(request.memoryCacheStorageAllowed)
        request.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(self.mocCache.images.count, 0)
        XCTAssertNil(self.manager.image(for: request))
        
        self.expect { fulfill in
            self.manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mocCache.images.count, 0)
        XCTAssertNil(self.manager.image(for: request))
    }
}

class ImageCacheTest: XCTestCase {
    var cache: ImageCache!
    var manager: ImageManager!
    var mockSessionManager: MockDataLoader!
    
    override func setUp() {
        super.setUp()
        
        self.cache = ImageCache()
        self.mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: self.mockSessionManager)
        self.manager = ImageManager(loader: loader, cache: self.cache)
    }
    
    func testThatImagesAreStoredInCache() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertNil(self.manager.image(for: request))
        
        self.expect { fulfill in
            self.manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
                }.resume()
        }
        self.wait()
        
        XCTAssertNotNil(self.manager.image(for: request))
        
        self.mockSessionManager.enabled = false
        
        self.expect { fulfill in
            self.manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
                }.resume()
        }
        self.wait()
    }
    
    #if os(iOS) || os(tvOS)
    func testThatImageAreRemovedOnMemoryWarnings() {
        let request = ImageRequest(url: defaultURL)
        self.manager.setImage(Image(), for: request)
        XCTAssertNotNil(self.manager.image(for: request))
        
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        XCTAssertNil(self.manager.image(for: request))
    }
    #endif
}
