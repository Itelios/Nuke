//
//  ImageCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class MockImageCacheTests: XCTestCase {
    var manager: ImageManager!
    var mocCache: MockImageCache!
    var mockSessionManager: MockDataLoader!
    
    override func setUp() {
        super.setUp()

        mocCache = MockImageCache()
        mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: mockSessionManager)
        manager = ImageManager(loader: loader, cache: mocCache)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatCacheWorks() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))

        expect { fulfill in
            manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        wait()
        
        XCTAssertEqual(mocCache.images.count, 1)
        XCTAssertNotNil(mocCache.image(for: request))
        
        mockSessionManager.enabled = false
        
        expect { fulfill in
            manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        wait()
    }
    
    func testThatStoreResponseMethodWorks() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
        
        mocCache.setImage(Image(), for: request)
        
        XCTAssertEqual(mocCache.images.count, 1)
        let image = mocCache.image(for: request)
        XCTAssertNotNil(image)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
        
        mocCache.setImage(Image(), for: request)
        
        XCTAssertEqual(mocCache.images.count, 1)
        let response = mocCache.image(for: request)
        XCTAssertNotNil(response)
        
        mocCache.removeImage(for: request)
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
    }
    
    func testThatCacheStorageCanBeDisabled() {
        var request = ImageRequest(url: defaultURL)
        XCTAssertTrue(request.memoryCacheStorageAllowed)
        request.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
        
        expect { fulfill in
            manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        wait()
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
    }
}

class ImageCacheTests: XCTestCase {
    var cache: ImageCache!
    var manager: ImageManager!
    var mockSessionManager: MockDataLoader!
    
    override func setUp() {
        super.setUp()
        
        cache = ImageCache()
        mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: mockSessionManager)
        manager = ImageManager(loader: loader, cache: cache)
    }
    
    func testThatImagesAreStoredInCache() {
        let request = ImageRequest(url: defaultURL)
        
        XCTAssertNil(cache.image(for: request))
        
        expect { fulfill in
            manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
                }.resume()
        }
        wait()
        
        XCTAssertNotNil(cache.image(for: request))
        
        mockSessionManager.enabled = false
        
        expect { fulfill in
            manager.task(with: request) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
                }.resume()
        }
        wait()
    }
    
    #if os(iOS) || os(tvOS)
    func testThatImageAreRemovedOnMemoryWarnings() {
        let request = ImageRequest(url: defaultURL)
        cache.setImage(Image(), for: request)
        XCTAssertNotNil(cache.image(for: request))
        
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        XCTAssertNil(cache.image(for: request))
    }
    #endif
}
