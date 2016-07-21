// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Abstract class for image tasks. Tasks are always part of the image manager, you create a task by calling one of the methods on ImageManager.
public class ImageTask: Hashable {
    public typealias ResultType = Result<Image, NSError>
    
    /**
     The state of the task. Allowed transitions include:
     - suspended -> [running, cancelled]
     - running -> [cancelled, completed]
     - cancelled -> []
     - completed -> []
     */
    public enum State {
        case suspended, running, cancelled, completed
    }
    
    // MARK: Obtainig General Task Information
    
    /// The request that task was created with.
    public let request: ImageRequest

    /// The response which is set when task is either completed or cancelled.
    public internal(set) var result: ResultType?

    /// Return hash value for the receiver.
    public var hashValue: Int { return identifier }
    
    /// Uniquely identifies the task within an image manager.
    public let identifier: Int
    
    
    // MARK: Configuring Task

    /// Initializes task with a given request and identifier.
    public init(request: ImageRequest, identifier: Int) {
        self.request = request
        self.identifier = identifier
    }


    // MARK: Obraining Task Progress
    
    /// Return current task progress. Initial value is (0, 0).
    public internal(set) var progress = Progress()
    
    /// A progress closure that gets periodically during the lifecycle of the task.
    public var progressHandler: ((progress: Progress) -> Void)?
    
    
    // MARK: Controlling Task State
    
    /// The current state of the task.
    public internal(set) var state: State = .suspended
    
    /// Resumes the task if suspended. Resume methods are nestable.
    public func resume() { fatalError("Abstract method") }
    
    /// Cancels the task if it hasn't completed yet. Calls a completion closure with an error value of { ImageManagerErrorDomain, ImageManagerErrorCancelled }.
    public func cancel() { fatalError("Abstract method") }
}

/// Compares two image tasks by reference.
public func ==(lhs: ImageTask, rhs: ImageTask) -> Bool {
    return lhs === rhs
}
