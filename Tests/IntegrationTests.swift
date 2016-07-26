// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class IntegrationTests: XCTestCase {
    var manager: Manager!

    override func setUp() {
        super.setUp()
        
        let loader = Loader(loader: MockDataLoader(), decoder: DataDecoder())
        let deduplicator = DeduplicatingLoader(with: loader)
        manager = Manager(loader: deduplicator, cache: nil)
    }

    // MARK: Thread-Safety
    
    func testThreadSafety() {
        runThreadSafetyTests(for: manager)
    }
}
