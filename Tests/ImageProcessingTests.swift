//
//  ImageProcessingTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 06/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import XCTest
import Nuke

class ImageProcessingTests: XCTestCase {
    var manager: ImageManager!
    var mockMemoryCache: MockImageCache!
    var mockSessionManager: MockDataLoader!

    override func setUp() {
        super.setUp()

        mockSessionManager = MockDataLoader()
        mockMemoryCache = MockImageCache()
        
        mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: mockSessionManager)
        manager = ImageManager(loader: loader, cache: mockMemoryCache)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Applying Filters

    func testThatImageIsProcessed() {
        var request = ImageRequest(url: defaultURL)
        request.processors = [MockImageProcessor(ID: "processor1")]

        expect { fulfill in
            manager.task(with: request) {
                XCTAssertEqual($0.1.value!.nk_test_processorIDs, ["processor1"])
                fulfill()
            }.resume()
        }
        wait()
    }

    func testThatProcessedImageIsMemCached() {
        expect { fulfill in
            var request = ImageRequest(url: defaultURL)
            request.processors = [MockImageProcessor(ID: "processor1")]

            manager.task(with: request) {
                XCTAssertNotNil($0.1.value)
                fulfill()
            }.resume()
        }
        wait()

        var request = ImageRequest(url: defaultURL)
        request.processors = [MockImageProcessor(ID: "processor1")]
        guard let image = manager.cache?.image(for: request) else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
    }

    func testThatCorrectFiltersAreAppiedWhenDataTaskIsReusedForMultipleRequests() {
        var request1 = ImageRequest(url: defaultURL)
        request1.processors = [MockImageProcessor(ID: "processor1")]

        var request2 = ImageRequest(url: defaultURL)
        request2.processors = [MockImageProcessor(ID: "processor2")]

        expect { fulfill in
            manager.task(with: request1) {
                XCTAssertEqual($0.1.value!.nk_test_processorIDs, ["processor1"])
                fulfill()
            }.resume()
        }

        expect { fulfill in
            manager.task(with: request2) {
                XCTAssertEqual($0.1.value!.nk_test_processorIDs, ["processor2"])
                fulfill()
            }.resume()
        }

        wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }

    // MARK: Composing Filters

    func testThatImageIsProcessedWithFilterComposition() {
        var request = ImageRequest(url: defaultURL)
        request.processors = [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")]

        expect { fulfill in
            manager.task(with: request) {
                XCTAssertEqual($0.1.value!.nk_test_processorIDs, ["processor1", "processor2"])
                fulfill()
                }.resume()
        }
        wait()
    }

    func testThatImageProcessedWithFilterCompositionIsMemCached() {
        expect { fulfill in
            var request = ImageRequest(url: defaultURL)
            request.processors = [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")]
            manager.task(with: request) {
                XCTAssertNotNil($0.1.value)
                fulfill()
            }.resume()
        }
        wait()

        var request = ImageRequest(url: defaultURL)
        request.processors = [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")]
        guard let image = manager.cache?.image(for: request) else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
    }
    
    func testThatImageFilterWorksWithHeterogeneousFilters() {
        let composition1 = ImageProcessorComposition(processors: [MockImageProcessor(ID: "ID1"), MockParameterlessImageProcessor()])
        let composition2 = ImageProcessorComposition(processors: [MockImageProcessor(ID: "ID1"), MockParameterlessImageProcessor()])
        let composition3 = ImageProcessorComposition(processors: [MockParameterlessImageProcessor(), MockImageProcessor(ID: "ID1")])
        let composition4 = ImageProcessorComposition(processors: [MockParameterlessImageProcessor(), MockImageProcessor(ID: "ID1"), MockImageProcessor(ID: "ID2")])
        XCTAssertEqual(composition1, composition2)
        XCTAssertNotEqual(composition1, composition3)
        XCTAssertNotEqual(composition1, composition4)
    }
}
