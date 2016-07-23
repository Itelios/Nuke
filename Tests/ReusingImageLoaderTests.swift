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

class ReusingImageLoaderTests: XCTestCase {
    var reuser: ReusingImageLoader!
    var loader: MockImageLoader!
    
    override func setUp() {
        super.setUp()
        
        loader = MockImageLoader()
        reuser = ReusingImageLoader(loader: loader)
    }

    func testThatTasksAreReused() {
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertTrue(ImageRequestLoadingEquator().isEqual(request1, to: request2))

        expect { fulfill in
            _ = reuser.loadImage(for: request1) { _ in
                fulfill()
            }
        }

        expect { fulfill in
            _ = reuser.loadImage(for: request2) { _ in
                fulfill()
            }
        }

        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1)
        }
    }
    
    func testThatTasksForRequestsWithDifferentCachePolicyAreNotReused() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        XCTAssertFalse(ImageRequestLoadingEquator().isEqual(request1, to: request2))
        
        expect { fulfill in
            _ = reuser.loadImage(for: request1) { _ in
                fulfill()
            }
        }
        
        expect { fulfill in
            _ = reuser.loadImage(for: request2) { _ in
                fulfill()
            }
        }
        
        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 2)
        }
    }
    
    func testThatTaskWithRemainingHandlersDontGetCancelled() {
        loader.queue.isSuspended = true

        let manager = ImageManager(loader: reuser, cache: nil)
        
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
        
        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertTrue(ImageRequestLoadingEquator().isEqual(request1, to: request2))
        
        expect { fulfill in
            var completedUnitCount: Int64 = 0
            _ = reuser.loadImage(for: request1, progress: { completed, total in
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
            _ = reuser.loadImage(for: request2, progress: { completed, total in
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
}
