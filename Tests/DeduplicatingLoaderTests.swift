//
//  ReusingImageLoaderTests.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 23/07/16.
//  Copyright © 2016 Alexander Grebenyuk. All rights reserved.
//

import Foundation

import XCTest
import Nuke

class DeduplicatingLoaderTests: XCTestCase {
    var deduplicator: DeduplicatingLoader!
    var loader: MockImageLoader!
    
    override func setUp() {
        super.setUp()
        
        loader = MockImageLoader()
        deduplicator = DeduplicatingLoader(loader: loader)
    }

    func testThatEquivalentRequestsAreDeduplicated() {
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertTrue(RequestLoadingEquator().isEqual(request1, to: request2))

        expect { fulfill in
            _ = deduplicator.loadImage(for: request1) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }

        expect { fulfill in
            _ = deduplicator.loadImage(for: request2) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }

        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1)
        }
    }
    
    func testThatNonEquivalentRequestsAreNotDeduplicated() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        XCTAssertFalse(RequestLoadingEquator().isEqual(request1, to: request2))
        
        expect { fulfill in
            _ = deduplicator.loadImage(for: request1) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        
        expect { fulfill in
            _ = deduplicator.loadImage(for: request2) { result in
                XCTAssertTrue(result.isSuccess)
                fulfill()
            }
        }
        
        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 2)
        }
    }
    
    func testThatDeduplicatedRequestIsNotCancelledAfterSingleUnsubsribe() {
        loader.queue.isSuspended = true

        let manager = Manager(loader: deduplicator, cache: nil)
        
        // We test it using Manager because Loader is not required
        // to call completion handler for cancelled requests.
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

        // Wait until task is started
        _ = expectNotification(MockImageLoader.DidStartTask, object: nil) { _ in
            task1.cancel()
            self.loader.queue.isSuspended = false
            return true
        }

        task1.resume()
        task2.resume()

        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1)
        }
    }
    
    func testThatProgressHandlersAreCalled() {
        loader.queue.isSuspended = true
        
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertTrue(RequestLoadingEquator().isEqual(request1, to: request2))
        
        expect { fulfill in
            var completedUnitCount: Int64 = 0
            _ = deduplicator.loadImage(for: request1, progress: { completed, total in
                completedUnitCount += 50
                XCTAssertEqual(completedUnitCount, completed)
                if completed == total {
                    fulfill()
                }
            }, completion: { _ in
                return
            })
        }
        
        expect { fulfill in
            var completedUnitCount: Int64 = 0
            _ = deduplicator.loadImage(for: request2, progress: { completed, total in
                completedUnitCount += 50
                XCTAssertEqual(completedUnitCount, completed)
                if completed == total {
                    fulfill()
                }
            }, completion: { _ in
                return
            })
        }
        
        // wait till both tasks are fully registered
        loader.queue.isSuspended = false
        
        wait()
    }
    
    func testThreadSafety() {
        for _ in 0..<500 {
            self.expect { fulfill in
                DispatchQueue.global().async {
                    let request = Request(url: URL(string: "\(defaultURL)/\(arc4random_uniform(10))")!)
                    let shouldCancel = arc4random_uniform(3) == 0
                    
                    let task = self.deduplicator.loadImage(for: request) {
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
