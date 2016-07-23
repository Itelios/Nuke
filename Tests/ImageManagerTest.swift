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
    var mockSessionManager: MockDataLoader!

    override func setUp() {
        super.setUp()

        mockSessionManager = MockDataLoader()
        let loader = ImageLoader(dataLoader: mockSessionManager)
        manager = ImageManager(loader: loader, cache: nil)
    }

    // MARK: Basics

    func testThatRequestIsCompelted() {
        expect { fulfill in
            manager.task(with: ImageRequest(url: defaultURL)) {
                XCTAssertNotNil($0.1.value, "")
                fulfill()
            }.resume()
        }
        wait()
    }

    func testThatTaskChangesStateWhenCompleted() {
        let task = expected { fulfill in
            return manager.task(with: defaultURL) { task, _ in
                XCTAssertTrue(task.state == .completed)
                fulfill()
            }
        }
        XCTAssertTrue(task.state == .suspended)
        task.resume()
        XCTAssertTrue(task.state == .running)
        wait()
    }

    func testThatTaskChangesStateOnCallersThreadWhenCompleted() {
        let expectation = expected()
        DispatchQueue.global(attributes: DispatchQueue.GlobalAttributes.qosDefault).async {
            let task = self.manager.task(with: defaultURL) { task, _ in
                XCTAssertTrue(task.state == .completed)
                expectation.fulfill()
            }
            XCTAssertTrue(task.state == .suspended)
            task.resume()
            XCTAssertTrue(task.state == .running)
        }
        wait()
    }

    // MARK: Cancellation

    func testThatResumedTaskIsCancelled() {
        mockSessionManager.enabled = false

        let task = expected { fulfill in
            return manager.task(with: defaultURL) { task, result in
                switch result.error! {
                    case .cancelled: break
                    default: XCTFail()
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

        wait()
    }

    func testThatSuspendedTaskIsCancelled() {
        let task = expected { fulfill in
            return manager.task(with: defaultURL) { task, result in
                switch result.error! {
                case .cancelled: break
                default: XCTFail()
                }
                XCTAssertTrue(task.state == .cancelled)
                fulfill()
            }
        }
        XCTAssertTrue(task.state == .suspended)
        task.cancel()
        XCTAssertTrue(task.state == .cancelled)
        wait()
    }

    func testThatSessionDataTaskIsCancelled() {
        mockSessionManager.enabled = false

        _ = expectNotification(MockURLSessionDataTaskDidResumeNotification)
        let task = manager.task(with: defaultURL)
        task.resume()
        wait()

        _ = expectNotification(MockURLSessionDataTaskDidCancelNotification)
        task.cancel()
        wait()
    }

    // MARK: Data Tasks Reusing

    func testThatDataTasksAreReused() {
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)

        expect { fulfill in
            manager.task(with: request1) { _ in
                fulfill()
            }.resume()
        }

        expect { fulfill in
            manager.task(with: request2) { _ in
                fulfill()
            }.resume()
        }

        wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }
    
    func testThatDataTasksWithDifferentCachePolicyAreNotReused() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        
        expect { fulfill in
            manager.task(with: request1) { _ in
                fulfill()
            }.resume()
        }
        
        expect { fulfill in
            manager.task(with: request2) { _ in
                fulfill()
            }.resume()
        }
        
        wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 2)
        }
    }
    
    func testThatDataTaskWithRemainingTasksDoesntGetCancelled() {
        mockSessionManager.enabled = false

        let task1 = expected { fulfill in
            return manager.task(with: defaultURL) {
                XCTAssertTrue($0.state == .cancelled)
                XCTAssertNil($1.value)
                fulfill()
            }
        }
        
        let task2 = expected { fulfill in
            return manager.task(with: defaultURL) {
                XCTAssertTrue($0.state == .completed)
                XCTAssertNotNil($1.value)
                fulfill()
            }
        }

        task1.resume()
        task2.resume()

        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: MockURLSessionDataTaskDidResumeNotification), object: nil, queue: nil) { _ in
            task1.cancel()
        }

        mockSessionManager.enabled = true
        wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }

    // MARK: Progress

    func testThatProgressClosureIsCalled() {
        let task = manager.task(with: defaultURL)
        XCTAssertEqual(task.progress.total, 0)
        XCTAssertEqual(task.progress.completed, 0)
        XCTAssertEqual(task.progress.fractionCompleted, 0.0)
        
        expect { fulfill in
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
        wait()
    }
    
    // MARK: Misc
    
    func testThatGetImageTasksMethodReturnsCorrectTasks() {
        mockSessionManager.enabled = false
        
        let task1 = manager.task(with: URL(string: "http://test1.com")!, completion: nil)
        let task2 = manager.task(with: URL(string: "http://test2.com")!, completion: nil)
        
        task1.resume()
        
        // task3 is not getting resumed
        
        expect { fulfill in
            let executingTasks = manager.tasks
            XCTAssertEqual(executingTasks.count, 1)
            XCTAssertTrue(executingTasks.contains(task1))
            XCTAssertTrue(task1.state == .running)
            XCTAssertFalse(executingTasks.contains(task2))
            XCTAssertTrue(task2.state == .suspended)
            fulfill()
        }
        wait()
    }
}
