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
    var mockSessionManager: MockDataLoader!

    override func setUp() {
        super.setUp()

        mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: mockSessionManager)
        manager = ImageManager(loader: loader, cache: nil)
    }

        func testThatPreheatingRequestsAreStopped() {
        mockSessionManager.enabled = false

        let preheater = ImagePreheater(manager: manager)

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockDataLoader.DidStartDataTask)
        preheater.startPreheating(for: [request])
        wait()

        _ = expectNotification(MockDataLoader.DidCancelDataTask)
        preheater.stopPreheating(for: [request])
        wait()
    }

    func testThatSimilarPreheatingRequestsAreStoppedWithSingleStopCall() {
        mockSessionManager.enabled = false

        let preheater = ImagePreheater(manager: manager)

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockDataLoader.DidStartDataTask)
        preheater.startPreheating(for: [request, request])
        preheater.startPreheating(for: [request])
        wait()

        _ = expectNotification(MockDataLoader.DidCancelDataTask)
        preheater.stopPreheating(for: [request])

        wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1, "")
        }
    }

    func testThatAllPreheatingRequestsAreStopped() {
        mockSessionManager.enabled = false

        let preheater = ImagePreheater(manager: manager)

        let request = ImageRequest(url: defaultURL)
        _ = expectNotification(MockDataLoader.DidStartDataTask)
        preheater.startPreheating(for: [request])
        wait(2)

        _ = expectNotification(MockDataLoader.DidCancelDataTask)
        preheater.stopPreheating()
        wait(2)
    }
}
