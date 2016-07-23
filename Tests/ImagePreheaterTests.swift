//
//  ImagePreheaterTests.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 23/07/16.
//  Copyright © 2016 Alexander Grebenyuk. All rights reserved.
//

import XCTest
import Nuke

class ImagePreheaterTests: XCTestCase {
    var manager: ImageManager!
    var loader: MockImageLoader!

    override func setUp() {
        super.setUp()

        loader = MockImageLoader()
        manager = ImageManager(loader: loader, cache: nil)
    }

    func testThatPreheatingRequestsAreStopped() {
        loader.queue.isSuspended = true

        let preheater = ImagePreheater(manager: manager)

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask)
        preheater.startPreheating(for: [request])
        wait()

        _ = expectNotification(MockImageLoader.DidCancelTask)
        preheater.stopPreheating(for: [request])
        wait()
    }

    func testThatSimilarPreheatingRequestsAreStoppedWithSingleStopCall() {
        loader.queue.isSuspended = true

        let preheater = ImagePreheater(manager: manager)

        let request = ImageRequest(url: defaultURL)
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

        let preheater = ImagePreheater(manager: manager)

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockImageLoader.DidStartTask)
        preheater.startPreheating(for: [request])
        wait(2)

        _ = expectNotification(MockImageLoader.DidCancelTask)
        preheater.stopPreheating()
        wait(2)
    }
}
