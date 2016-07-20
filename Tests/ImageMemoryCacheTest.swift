//
//  ImageMemoryCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class ImageMockMemoryCacheTest: XCTestCase {
    var manager: ImageManager!
    var mockMemoryCache: MockImageMemoryCache!
    var mockSessionManager: MockImageDataLoader!
    
    override func setUp() {
        super.setUp()

        self.mockMemoryCache = MockImageMemoryCache()
        self.mockSessionManager = MockImageDataLoader()
        let loader = ImageLoader(dataLoader: self.mockSessionManager)
        self.manager = ImageManager(loader: loader, cache: self.mockMemoryCache)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatMemoryCacheWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))

        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 1)
        XCTAssertNotNil(self.manager.imageForRequest(request))
        
        self.mockSessionManager.enabled = false
        
        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))
        
        self.manager.setImage(Image(), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 1)
        let response = self.manager.imageForRequest(request)
        XCTAssertNotNil(response)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))
        
        self.manager.setImage(Image(), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 1)
        let response = self.manager.imageForRequest(request)
        XCTAssertNotNil(response)
        
        self.manager.removeImageForRequest(request)
        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))
    }
    
    func testThatMemoryCacheStorageCanBeDisabled() {
        var request = ImageRequest(URL: defaultURL)
        XCTAssertTrue(request.memoryCacheStorageAllowed)
        request.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))
        
        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))
    }

    func testThatAllCachedImageAreRemoved() {
        let request = ImageRequest(URL: defaultURL)
        self.manager.setImage(Image(), forRequest: request)

        XCTAssertEqual(self.mockMemoryCache.images.count, 1)

        self.manager.removeAllCachedImages()

        XCTAssertEqual(self.mockMemoryCache.images.count, 0)
        XCTAssertNil(self.manager.imageForRequest(request))
    }
}

class ImageMemoryCacheTest: XCTestCase {
    var cache: ImageMemoryCache!
    var manager: ImageManager!
    var mockSessionManager: MockImageDataLoader!
    
    override func setUp() {
        super.setUp()
        
        self.cache = ImageMemoryCache()
        self.mockSessionManager = MockImageDataLoader()
        let loader = ImageLoader(dataLoader: self.mockSessionManager)
        self.manager = ImageManager(loader: loader, cache: self.cache)
    }
    
    func testThatImagesAreStoredInMemoryCache() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertNil(self.manager.imageForRequest(request))
        
        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
                }.resume()
        }
        self.wait()
        
        XCTAssertNotNil(self.manager.imageForRequest(request))
        
        self.mockSessionManager.enabled = false
        
        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
                }.resume()
        }
        self.wait()
    }
    
    #if os(iOS) || os(tvOS)
    func testThatImageAreRemovedOnMemoryWarnings() {
        let request = ImageRequest(URL: defaultURL)
        self.manager.setImage(Image(), forRequest: request)
        XCTAssertNotNil(self.manager.imageForRequest(request))
        
        NSNotificationCenter.defaultCenter().postNotificationName(UIApplicationDidReceiveMemoryWarningNotification, object: nil)
        
        XCTAssertNil(self.manager.imageForRequest(request))
    }
    #endif
}
