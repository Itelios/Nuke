// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class PreheaterTests: XCTestCase {
    var manager: Manager!
    var loader: MockImageLoader!
    var preheater: Preheater!

    override func setUp() {
        super.setUp()

        loader = MockImageLoader()
        manager = Manager(loader: loader, cache: nil)
        preheater = Preheater(manager: manager)
    }

    func testThatPreheatingRequestsAreStopped() {
        loader.queue.isSuspended = true

        let request = Request(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask)
        preheater.startPreheating(for: [request])
        wait()

        _ = expectNotification(MockImageLoader.DidCancelTask)
        preheater.stopPreheating(for: [request])
        wait()
    }

    func testThatEquaivalentRequestsAreStoppedWithSingleStopCall() {
        loader.queue.isSuspended = true

        let request = Request(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask)
        preheater.startPreheating(for: [request, request])
        preheater.startPreheating(for: [request])
        wait()

        _ = expectNotification(MockImageLoader.DidCancelTask)
        preheater.stopPreheating(for: [request])

        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1, "")
        }
    }

    func testThatAllPreheatingRequestsAreStopped() {
        loader.queue.isSuspended = true

        let request = Request(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask)
        preheater.startPreheating(for: [request])
        wait(2)

        _ = expectNotification(MockImageLoader.DidCancelTask)
        preheater.stopPreheating()
        wait(2)
    }
}
