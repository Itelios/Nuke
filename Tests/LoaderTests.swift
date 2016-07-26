// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class LoaderTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()
        
        dataLoader = MockDataLoader()
        loader = Loader(loader: dataLoader, decoder: DataDecoder())
    }

    func testThreadSafety() {
        runThreadSafetyTests(for: loader)
    }
}

class LoaderErrorHandlingTests: XCTestCase {

    func testThatLoadingFailedErrorIsReturned() {
        let dataLoader = MockDataLoader()
        let loader = Loader(loader: dataLoader, decoder: DataDecoder())

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[defaultURL] = .failure(AnyError(expectedError))

        expect { fulfill in
            _ = loader.loadImage(for: Request(url: defaultURL)) { result in
                let err = (result.error?.cause as? Loader.Error)?.loadingError
                XCTAssertNotNil(err)
                XCTAssertEqual((err?.cause as? NSError)?.code, expectedError.code)
                XCTAssertEqual((err?.cause as? NSError)?.domain, expectedError.domain)
                fulfill()
            }
        }
        wait()
    }

    func testThatDecodingFailedErrorIsReturned() {
        let loader = Loader(loader: MockDataLoader(), decoder: MockFailingDecoder())

        expect { fulfill in
            _ = loader.loadImage(for: Request(url: defaultURL)) { result in
                XCTAssertTrue(((result.error?.cause as? Loader.Error)?.isDecodingError)!)
                fulfill()
            }
        }
        wait()
    }

    func testThatProcessingFailedErrorIsReturned() {
        let loader = Loader(loader: MockDataLoader(), decoder: DataDecoder())

        var request = Request(url: defaultURL)
        request.add(processor: MockFailingProcessor())

        expect { fulfill in
            _ = loader.loadImage(for: request) { result in
                XCTAssertTrue(((result.error?.cause as? Loader.Error)?.isProcessingError)!)
                fulfill()
            }
        }
        wait()
    }
}
