//
//  ImageMemoryCacheTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/15/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class ImageMemoryCacheTest: XCTestCase {
    var manager: ImageManager!
    var mockMemoryCache: MockImageMemoryCache!
    var mockSessionManager: MockImageDataLoader!
    
    override func setUp() {
        super.setUp()

        self.mockMemoryCache = MockImageMemoryCache()
        self.mockSessionManager = MockImageDataLoader()
        let loader = ImageLoader(configuration: ImageLoaderConfiguration(dataLoader: self.mockSessionManager))
        self.manager = ImageManager(configuration: ImageManagerConfiguration(loader: loader, cache: self.mockMemoryCache))
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testThatMemoryCacheWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))

        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        XCTAssertNotNil(self.manager.responseForRequest(request))
        
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
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
        
        self.manager.setResponse(ImageCachedResponse(image: Image()), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        let response = self.manager.responseForRequest(request)
        XCTAssertNotNil(response)
    }
    
    func testThatRemoveResponseMethodWorks() {
        let request = ImageRequest(URL: defaultURL)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
        
        self.manager.setResponse(ImageCachedResponse(image: Image()), forRequest: request)
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)
        let response = self.manager.responseForRequest(request)
        XCTAssertNotNil(response)
        
        self.manager.removeResponseForRequest(request)
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
    }
    
    func testThatMemoryCacheStorageCanBeDisabled() {
        var request = ImageRequest(URL: defaultURL)
        XCTAssertTrue(request.memoryCacheStorageAllowed)
        request.memoryCacheStorageAllowed = false // Test default value
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
        
        self.expect { fulfill in
            self.manager.taskWith(request) { _, response in
                XCTAssertTrue(response.isSuccess)
                fulfill()
            }.resume()
        }
        self.wait()
        
        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
    }

    func testThatAllCachedImageAreRemoved() {
        let request = ImageRequest(URL: defaultURL)
        self.manager.setResponse(ImageCachedResponse(image: Image()), forRequest: request)

        XCTAssertEqual(self.mockMemoryCache.responses.count, 1)

        self.manager.removeAllCachedImages()

        XCTAssertEqual(self.mockMemoryCache.responses.count, 0)
        XCTAssertNil(self.manager.responseForRequest(request))
    }
}
