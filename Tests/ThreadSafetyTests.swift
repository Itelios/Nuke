// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

extension XCTestCase {
    func runThreadSafetyTests(for manager: Manager) {
        for _ in 0..<500 {
            self.expect { fulfill in
                DispatchQueue.global().async {
                    let request = Request(url: URL(string: "\(defaultURL)/\(arc4random_uniform(10))")!)
                    let shouldCancel = arc4random_uniform(3) == 0
                    
                    let task = manager.task(with: request) { task, response in
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
    
    func runThreadSafetyTests(for loader: Loading) {
        for _ in 0..<500 {
            self.expect { fulfill in
                DispatchQueue.global().async {
                    let request = Request(url: URL(string: "\(defaultURL)/\(arc4random_uniform(10))")!)
                    let shouldCancel = arc4random_uniform(3) == 0
                    
                    let task = loader.loadImage(for: request, progress: nil) {
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
