// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ProcessingTests: XCTestCase {
    var manager: Manager!
    var mockMemoryCache: MockCache!
    var mockSessionManager: MockDataLoader!

    override func setUp() {
        super.setUp()

        mockSessionManager = MockDataLoader()
        mockMemoryCache = MockCache()
        
        mockSessionManager = MockDataLoader()
        let loader = Loader(loader: mockSessionManager, decoder: ImageDataDecoder())
        manager = Manager(loader: loader, cache: mockMemoryCache)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Applying Filters

    func testThatImageIsProcessed() {
        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))

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
            var request = Request(url: defaultURL)
            request.add(processor: MockImageProcessor(ID: "processor1"))

            manager.task(with: request) {
                XCTAssertNotNil($0.1.value)
                fulfill()
            }.resume()
        }
        wait()

        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))
        guard let image = manager.cache?.image(for: request) else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
    }

    // MARK: Composing Filters

    func testThatImageIsProcessedWithFilterComposition() {
        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))
        request.add(processor: MockImageProcessor(ID: "processor2"))

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
            var request = Request(url: defaultURL)
            request.add(processor: MockImageProcessor(ID: "processor1"))
            request.add(processor: MockImageProcessor(ID: "processor2"))
            manager.task(with: request) {
                XCTAssertNotNil($0.1.value)
                fulfill()
            }.resume()
        }
        wait()

        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))
        request.add(processor: MockImageProcessor(ID: "processor2"))
        guard let image = manager.cache?.image(for: request) else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
    }
}
