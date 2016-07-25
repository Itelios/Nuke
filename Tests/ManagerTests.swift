// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

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
    
    // MARK: Basics
    
    func testThatRequestIsCompelted() {
        expect { fulfill in
            manager.task(with: Request(url: defaultURL)) { task, response in
                XCTAssertNil(response.error)
                XCTAssertNotNil(response.value)
                fulfill()
            }.resume()
        }
        wait()
    }

    func testThatRequestIsFailed() {
        loader.results[defaultURL] = .failure(AnyError("failed"))
        expect { fulfill in
            manager.task(with: Request(url: defaultURL)) { task, response in
                XCTAssertNotNil(response.error)
                XCTAssertNil(response.value)
                fulfill()
            }.resume()
        }
        wait()
    }
    
    func testThatLoadingErrorGetsRelayed() {
        loader.results[defaultURL] = .failure(AnyError("failed"))
        expect { fulfill in
            manager.task(with: Request(url: defaultURL)) { task, response in
                switch response.error! {
                case let .loadingFailed(error):
                    XCTAssertTrue((error.cause as? String) == "failed")
                default: XCTFail()
                }
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

        task.resume()
        task.cancel()
        
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
    
    func testThatLoadTaskIsCancelledWithReEntrantCancel() {
        loader.queue.isSuspended = true
        
        let task = expected { fulfill in
            return manager.task(with: defaultURL) { _ in
                fulfill()
            }
        }
        
        // Wait until task is started
        _ = expectNotification(MockImageLoader.DidStartTask) { _ in
            task.cancel()
            return true
        }
        
        task.resume()
        
        _ = expectNotification(MockImageLoader.DidCancelTask)
        
        wait()
    }
    
    // MARK: Progress

    func testThatProgressClosureIsCalled() {
        let task = manager.task(with: defaultURL)
        XCTAssertEqual(task.progress.total, 0)
        XCTAssertEqual(task.progress.completed, 0)
        
        expect { fulfill in
            var completedUnitCount: Int64 = 0
            task.progressHandler = { progress in
                completedUnitCount += 50
                XCTAssertEqual(completedUnitCount, progress.completed)
                XCTAssertEqual(100, progress.total)
                XCTAssertEqual(completedUnitCount, task.progress.completed)
                XCTAssertEqual(100, task.progress.total)
                if task.progress.completed == 100 {
                    fulfill()
                }
            }
        }
        task.resume()
        wait()
    }
    
    // MARK: Get Tasks
    
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

    // MARK: Thread-Safety
    
    func testThreadSafety() {
        for _ in 0..<500 {
            self.expect { fulfill in
                DispatchQueue.global().async {
                    let request = Request(url: URL(string: "\(defaultURL)/\(arc4random_uniform(10))")!)
                    let shouldCancel = arc4random_uniform(3) == 0
                    
                    let task = self.manager.task(with: request) { task, response in
                        if shouldCancel {
                            // do nothing, we can't expect that task
                            // would get cancelled before it completes
                        } else {
                            XCTAssertTrue(response.isSuccess)
                        }
                        fulfill()
                    }
                    task.resume()
                    
                    if shouldCancel {
                        DispatchQueue.global().async {
                            task.cancel()
                        }
                    }
                }
            }
        }
        
        wait()
    }
}
