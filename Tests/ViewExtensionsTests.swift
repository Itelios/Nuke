// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ViewExtensionsTests: XCTestCase {
    var view: ImageView!
    var manager: Manager!
    var loader: MockImageLoader!
    
    override func setUp() {
        super.setUp()
        
        view = ImageView()
        loader = MockImageLoader()
        manager = Manager(loader: loader, cache: MockCache())
        view.nk_context.manager = manager
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            view.nk_context.handler = { response, _ in
                XCTAssertNotNil(response.value)
                fulfill()
            }
        }
        view.nk_setImage(with: defaultURL)
        wait()
    }

    func testThatPreviousTaskIsCancelledWhenNewOneIsCreated() {
        expect { fulfill in
            view.nk_context.handler = { response, _ in
                XCTAssertTrue(response.isSuccess)
                fulfill() // should be called just once
            }
        }

        view.nk_setImage(with: URL(string: "http://test.com/1")!)
        let task1 = view.nk_context.task!
        XCTAssertNotNil(task1)
        
        // Manager resumes tasks asynchronously so it might either
        // resume task at this points or not
        var task1DidResume = task1.state == .running
        _ = expectNotification(Task.DidUpdateState, object: task1) { _ in
            if !task1DidResume {
                XCTAssertTrue(task1.state == .running)
                task1DidResume = true
                return false
            }
            XCTAssertTrue(task1.state == .cancelled)
            return true
        }
        
        view.nk_setImage(with: URL(string: "http://test.com/2")!)
        let task2 = view.nk_context.task!
        XCTAssertNotNil(task2)
        XCTAssertTrue(task1 !== task2)
        
        wait()
    }
    
    func testThatSecondResponseIsReturnedFromMemoryCache() {
        expect { fulfill in
            view.nk_context.handler = { response, isFromMemoryCache in
                XCTAssertNotNil(response.value)
                XCTAssertFalse(isFromMemoryCache)
                fulfill()
            }
        }
        view.nk_setImage(with: defaultURL)
        wait()
        
        var didSetImage = false
        view.nk_context.handler = { response, isFromMemoryCache in
            XCTAssertNotNil(response.value)
            XCTAssertTrue(isFromMemoryCache)
            didSetImage = true
        }
        view.nk_setImage(with: defaultURL)
        XCTAssertTrue(didSetImage)
    }
    
    func testThatTaskGetsCancellonOnViewDeallocation() {
        _ = expectNotification(MockImageLoader.DidCancelTask)
        view.nk_setImage(with: defaultURL)
        view = nil
        wait()
    }
}
