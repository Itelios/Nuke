//
//  ManagerTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2016 Alexander Grebenyuk (github.com/kean). All rights reserved.
//

import XCTest
import Nuke

class ManagerTests: XCTestCase {
    var manager: Manager!
    var loader: MockImageLoader!

    override func setUp() {
        super.setUp()

        loader = MockImageLoader()
        manager = Manager(loader: loader, cache: nil)
    }

    func testThatRequestIsCompelted() {
        expect { fulfill in
            manager.task(with: Request(url: defaultURL)) {
                XCTAssertNotNil($0.1.value, "")
                fulfill()
            }.resume()
        }
        wait()
    }

    // MARK: Tasks State
    
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
        loader.queue.isSuspended = true

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

        // Wait until task is started
        _ = expectNotification(MockImageLoader.DidStartTask) { _ in
            // Here's a potential problem: as a result of this
            // task gets cancelled during the resume()
            // which leads to MockTask now being cancelled
            task.cancel()
            return true
        }

        task.resume()
        XCTAssertTrue(task.state == .cancelled)
        
        _ = expectNotification(MockImageLoader.DidCancelTask)

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

    func testThatDataTaskIsCancelled() {
        loader.queue.isSuspended = true

        _ = expectNotification(MockImageLoader.DidStartTask)
        let task = manager.task(with: defaultURL)
        task.resume()
        wait()

        _ = expectNotification(MockImageLoader.DidCancelTask)
        task.cancel()
        wait()
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
    
    func testThatGetTasksMethodReturnsCorrectTasks() {
        loader.queue.isSuspended = true
        
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
