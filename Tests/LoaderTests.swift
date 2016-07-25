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
        loader = Loader(dataLoader: dataLoader, dataDecoder: ImageDataDecoder())
    }
    
    func testThreadSafety() {
        for _ in 0..<500 {
            self.expect { fulfill in
                DispatchQueue.global().async {
                    let request = Request(url: URL(string: "\(defaultURL)/\(arc4random_uniform(10))")!)
                    let shouldCancel = arc4random_uniform(3) == 0
                    
                    let task = self.loader.loadImage(for: request) {
                        if shouldCancel {
                            // do nothing, we don't expect completion on cancel
                        } else {
                            XCTAssertTrue($0.isSuccess)
                            fulfill()
                        }
                    }
                    
                    if shouldCancel {
                        DispatchQueue.global().async {
                            task.cancel()
                            fulfill()
                        }
                    }
                }
            }
        }
        
        wait()
    }
}
