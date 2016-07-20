//
//  ImageManagerTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class ImageManagerTest: XCTestCase {
    var manager: ImageManager!
    var mockSessionManager: MockImageDataLoader!

    override func setUp() {
        super.setUp()

        self.mockSessionManager = MockImageDataLoader()
        let loader = ImageLoader(dataLoader: self.mockSessionManager)
        self.manager = ImageManager(loader: loader, cache: nil)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Basics

    func testThatRequestIsCompelted() {
        self.expect { fulfill in
            self.manager.task(with: ImageRequest(url: defaultURL)) {
                XCTAssertNotNil($0.1.image, "")
                fulfill()
            }.resume()
        }
        self.wait()
    }

    func testThatTaskChangesStateWhenCompleted() {
        let task = self.expected { fulfill in
            return self.manager.task(with: defaultURL) { task, _ in
                XCTAssertTrue(task.state == .completed)
                fulfill()
            }
        }
        XCTAssertTrue(task.state == .suspended)
        task.resume()
        XCTAssertTrue(task.state == .running)
        self.wait()
    }

    func testThatTaskChangesStateOnCallersThreadWhenCompleted() {
        let expectation = self.expectation()
        DispatchQueue.global(attributes: DispatchQueue.GlobalAttributes.qosDefault).async {
            let task = self.manager.task(with: defaultURL) { task, _ in
                XCTAssertTrue(task.state == .completed)
                expectation.fulfill()
            }
            XCTAssertTrue(task.state == .suspended)
            task.resume()
            XCTAssertTrue(task.state == .running)
        }
        self.wait()
    }

    // MARK: Cancellation

    func testThatResumedTaskIsCancelled() {
        self.mockSessionManager.enabled = false

        let task = self.expected { fulfill in
            return self.manager.task(with: defaultURL) { task, response in
                switch response {
                case .success(_): XCTFail()
                case let .failure(error):
                    XCTAssertEqual((error as NSError).domain, ImageManagerErrorDomain, "")
                    XCTAssertEqual((error as NSError).code, ImageManagerErrorCode.cancelled.rawValue, "")
                }
                XCTAssertTrue(task.state == .cancelled)
                fulfill()
            }
        }

        XCTAssertTrue(task.state == .suspended)
        task.resume()
        XCTAssertTrue(task.state == .running)
        task.cancel()
        XCTAssertTrue(task.state == .cancelled)

        self.wait()
    }

    func testThatSuspendedTaskIsCancelled() {
        let task = self.expected { fulfill in
            return self.manager.task(with: defaultURL) { task, response in
                switch response {
                case .success(_): XCTFail()
                case let .failure(error):
                    XCTAssertEqual((error as NSError).domain, ImageManagerErrorDomain, "")
                    XCTAssertEqual((error as NSError).code, ImageManagerErrorCode.cancelled.rawValue, "")
                }
                XCTAssertTrue(task.state == .cancelled)
                fulfill()
            }
        }
        XCTAssertTrue(task.state == .suspended)
        task.cancel()
        XCTAssertTrue(task.state == .cancelled)
        self.wait()
    }

    func testThatSessionDataTaskIsCancelled() {
        self.mockSessionManager.enabled = false

        _ = self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        let task = self.manager.task(with: defaultURL)
        task.resume()
        self.wait()

        _ = self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        task.cancel()
        self.wait()
    }

    // MARK: Data Tasks Reusing

    func testThatDataTasksAreReused() {
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)

        self.expect { fulfill in
            self.manager.task(with: request1) { _ in
                fulfill()
            }.resume()
        }

        self.expect { fulfill in
            self.manager.task(with: request2) { _ in
                fulfill()
            }.resume()
        }

        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }
    
    func testThatDataTasksWithDifferentCachePolicyAreNotReused() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        
        self.expect { fulfill in
            self.manager.task(with: request1) { _ in
                fulfill()
            }.resume()
        }
        
        self.expect { fulfill in
            self.manager.task(with: request2) { _ in
                fulfill()
            }.resume()
        }
        
        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 2)
        }
    }
    
    func testThatDataTaskWithRemainingTasksDoesntGetCancelled() {
        self.mockSessionManager.enabled = false

        let task1 = self.expected { fulfill in
            return self.manager.task(with: defaultURL) {
                XCTAssertTrue($0.state == .cancelled)
                XCTAssertNil($1.image)
                fulfill()
            }
        }
        
        let task2 = self.expected { fulfill in
            return self.manager.task(with: defaultURL) {
                XCTAssertTrue($0.state == .completed)
                XCTAssertNotNil($1.image)
                fulfill()
            }
        }

        task1.resume()
        task2.resume()

        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: MockURLSessionDataTaskDidResumeNotification), object: nil, queue: nil) { _ in
            task1.cancel()
        }

        self.mockSessionManager.enabled = true
        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }

    // MARK: Progress

    func testThatProgressClosureIsCalled() {
        let task = self.manager.task(with: defaultURL)
        XCTAssertEqual(task.progress.total, 0)
        XCTAssertEqual(task.progress.completed, 0)
        XCTAssertEqual(task.progress.fractionCompleted, 0.0)
        
        self.expect { fulfill in
            var fractionCompleted = 0.0
            var completedUnitCount: Int64 = 0
            task.progressHandler = { progress in
                fractionCompleted += 0.5
                completedUnitCount += 50
                XCTAssertEqual(completedUnitCount, progress.completed)
                XCTAssertEqual(100, progress.total)
                XCTAssertEqual(completedUnitCount, task.progress.completed)
                XCTAssertEqual(100, task.progress.total)
                XCTAssertEqual(fractionCompleted, task.progress.fractionCompleted)
                if task.progress.fractionCompleted == 1.0 {
                    fulfill()
                }
            }
        }
        task.resume()
        self.wait()
    }

    // MARK: Preheating

    func testThatPreheatingRequestsAreStopped() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(url: defaultURL)
        _ = self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.manager.startPreheating(for: [request])
        self.wait()

        _ = self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        self.manager.stopPreheating(for: [request])
        self.wait()
    }

    func testThatSimilarPreheatingRequestsAreStoppedWithSingleStopCall() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(url: defaultURL)
        _ = self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.manager.startPreheating(for: [request, request])
        self.manager.startPreheating(for: [request])
        self.wait()

        _ = self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        self.manager.stopPreheating(for: [request])

        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1, "")
        }
    }

    func testThatAllPreheatingRequestsAreStopped() {
        self.mockSessionManager.enabled = false

        let request = ImageRequest(url: defaultURL)
        _ = self.expectNotification(MockURLSessionDataTaskDidResumeNotification)
        self.manager.startPreheating(for: [request])
        self.wait(2)

        _ = self.expectNotification(MockURLSessionDataTaskDidCancelNotification)
        self.manager.stopPreheating()
        self.wait(2)
    }

    // MARK: Invalidation

    func testThatInvalidateAndCancelMethodCancelsOutstandingRequests() {
        self.mockSessionManager.enabled = false

        // More than 1 image task!
        self.manager.task(with: defaultURL, completion: nil).resume()
        self.manager.task(with: URL(string: "http://test2.com")!, completion: nil).resume()
        var callbackCount = 0
        _ = self.expectNotification(MockURLSessionDataTaskDidCancelNotification) { _ in
            callbackCount += 1
            return callbackCount == 2
        }
        self.manager.invalidateAndCancel()
        self.wait()
    }
    
    // MARK: Misc
    
    func testThatGetImageTasksMethodReturnsCorrectTasks() {
        self.mockSessionManager.enabled = false
        
        let task1 = self.manager.task(with: URL(string: "http://test1.com")!, completion: nil)
        let task2 = self.manager.task(with: URL(string: "http://test2.com")!, completion: nil)
        
        task1.resume()
        
        // task3 is not getting resumed
        
        self.expect { fulfill in
            let (executingTasks, _) = self.manager.tasks
            XCTAssertEqual(executingTasks.count, 1)
            XCTAssertTrue(executingTasks.contains(task1))
            XCTAssertTrue(task1.state == .running)
            XCTAssertFalse(executingTasks.contains(task2))
            XCTAssertTrue(task2.state == .suspended)
            fulfill()
        }
        self.wait()
    }
}
