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
        loader = Loader(loader: dataLoader, decoder: ImageDataDecoder())
    }
    
    func testThreadSafety() {
        runThreadSafetyTests(for: loader)
    }
}
