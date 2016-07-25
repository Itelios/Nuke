// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class MockCacheTests: XCTestCase {
    var manager: Manager!
    var mocCache: MockCache!
    var mockSessionManager: MockDataLoader!
    
    override func setUp() {
        super.setUp()

        mocCache = MockCache()
        mockSessionManager = MockDataLoader()
        let loader = Loader(loader: mockSessionManager, decoder: ImageDataDecoder())
        manager = Manager(loader: loader, cache: mocCache)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatCacheWorks() {
        let request = Request(url: defaultURL)
        
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
        let request = Request(url: defaultURL)
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
        
        mocCache.setImage(Image(), for: request)
        
        XCTAssertEqual(mocCache.images.count, 1)
        let image = mocCache.image(for: request)
        XCTAssertNotNil(image)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = Request(url: defaultURL)
        
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
        let request = Request(url: defaultURL)
        var options = Manager.Options()
        XCTAssertTrue(options.memoryCacheStorageAllowed)
        options.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
        
        expect { fulfill in
            manager.task(with: request, options: options) { _, result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }.resume()
        }
        wait()
        
        XCTAssertEqual(mocCache.images.count, 0)
        XCTAssertNil(mocCache.image(for: request))
    }
}

class CacheTests: XCTestCase {
    var cache: Nuke.Cache!
    var manager: Manager!
    var mockSessionManager: MockDataLoader!
    
    override func setUp() {
        super.setUp()
        
        cache = Cache()
        mockSessionManager = MockDataLoader()
        let loader = Loader(loader: mockSessionManager, decoder: ImageDataDecoder())
        manager = Manager(loader: loader, cache: cache)
    }
    
    func testThatImagesAreStoredInCache() {
        let request = Request(url: defaultURL)
        
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
        let request = Request(url: defaultURL)
        cache.setImage(Image(), for: request)
        XCTAssertNotNil(cache.image(for: request))
        
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        XCTAssertNil(cache.image(for: request))
    }
    #endif
}
