//
//  Session.swift
//
//  Copyright (c) 2014 Weipin Xia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import UIKit

@objc protocol SessionDelegate {
    @optional func sessionShouldRetryCycle(session: Session, cycle: Cycle, error: NSError?) -> Bool;
    @optional func sessionShouldTreatStatusCodeAsFailure(session: Session, status: Int) -> Bool;
}

/*!
 * @discussion
 * This class manages Cycle objects. You can also threat this class as a wrapper 
 * around NSURLSession and its delegates.
 */
class Session: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate,
NSURLSessionDataDelegate {
     // TODO: Type Variable
    let PreservedHTTPHeadersKey = "PreservedHTTPHeaders"
    let PreservedHTTPQueryParametersKey = "PreservedHTTPQueryParameters"

    weak var delegate: SessionDelegate? = nil

/*!
 * The NSURLSession takes care of the major HTTP operations.
 */
    var core: NSURLSession!

/*!
 * The operation queue that the delegate related "callback" blocks will be added
 * to. This queue will also be set as NSURLSession's delete queue.
 */
    var delegateQueue: NSOperationQueue

/*!
 * The operation queue that the work related "callback" blocks will be added to.
 */
    var workerQueue: NSOperationQueue

/*!
 * An array of Processor subclass objects.
 */
    var requestProcessors = [Processor]()

/*!
 * An array of Processor subclass objects.
 */
    var responseProcessors = [Processor]()

/*!
 * Seconds to wait before a retry should be attempted.
 */
    var retryDelay: dispatch_time_t = 3
/*!
 * An array of Authentication subclass objects.
 */
    var authentications = [Authentication]()

    var cycles = [Cycle]()

    let RetryPolicyMaximumRetryCount = 3 // TODO, use Type Variable

/*!
 * @discussion 
 * The NetworkActivityIndicator manages the display of
 * network activity indicator. The default value is the singleton of the class.
 * You can set it as nil (don't display network spinning gear in status bar), or
 * set it as an object of NetworkActivityIndicator subclass to custom the display
 * logic.
 */
    var networkActivityIndicator :NetworkActivityIndicator?

    var preservedHTTPHeaders = Dictionary<String, String>()
    var preservedHTTPQueryParameters = Dictionary<String, [String]>()

/*!
 * @abstract 
 * Return the default singleton Session.
 */
    class func defaultSession() -> Session {
        struct Singleton {
            static var instance: Session? = nil
            static var onceToken: dispatch_once_t = 0
        }

        dispatch_once(&Singleton.onceToken) {
            Singleton.instance = self()
        }

        return Singleton.instance!
    }

/*!
 * @abstract 
 * Initialize a Session object
 *
 * @param configuration 
 * The NSURLSessionConfiguration the NSURLSession will be initialized with. 
 * If nil, the result of NSURLSessionConfiguration.defaultSessionConfiguration()
 * will be used.
 *
 * @param delegateQueue 
 * The operation queue that the delegate related "callback" blocks will be added 
 * to. This queue will also be set as NSURLSession's delete queue. If nil, the 
 * result of NSOperationQueue.mainQueue() will be used.
 *
 * @param workerQueue 
 * The operation queue that the work related "callback" blocks will be added to. 
 * If nil, a NSOperationQueue object will be created so the blocks will be run 
 * asynchronously on a separate thread.
 */
    @required init(configuration: NSURLSessionConfiguration? = nil,
    delegateQueue: NSOperationQueue? = nil,
    workerQueue: NSOperationQueue? = nil) {
        var c = configuration
        if !c {
            c = NSURLSessionConfiguration.defaultSessionConfiguration()
        }
        if let delegate = delegateQueue {
            self.delegateQueue = delegate
        } else {
            self.delegateQueue = NSOperationQueue.mainQueue()
        }
        if let delegate = workerQueue {
            self.workerQueue = delegate
        } else {
            self.workerQueue = NSOperationQueue()
        }

        self.networkActivityIndicator = NetworkActivityIndicator.sharedInstance()

        super.init()
        self.core = NSURLSession(configuration: c, delegate: self,
                                 delegateQueue: self.delegateQueue)
    }

    func indexOfCycle(cycle: Cycle) -> Int? {
        var index: Int?
        for (i, object) in enumerate(self.cycles) {
            if object !== cycle {
                continue
            }
            index = i
            break
        }
        return index
    }

/*!
 * @abstract 
 * Add a Cycle to the internal array.
 *
 * @param cycle
 * The Cycle to add.
 */
    func addCycle(cycle: Cycle) {
        if let index = self.indexOfCycle(cycle) {
            assert(false)
            return
        }

        self.cycles.append(cycle)
    }

/*!
 * @abstract 
 * Remove a Cycle from the internal array.
 *
 * @param cycle
 * The Cycle to remove.
 */
    func removeCycle(cycle: Cycle) {
        var index = indexOfCycle(cycle)
        if index {
            self.cycles.removeAtIndex(index!)
        }
    }

    func cycleForTask(task: NSURLSessionTask) -> Cycle? {
        var cycle: Cycle?
        for i in self.cycles {
            if i.core !== task {
                continue
            }
            cycle = i
            break
        }
        return cycle
    }

    func shouldRetry(solicited: Bool, retriedCount: Int, request: Request,
    response:Response, error: NSError!) -> Bool {
        if solicited {
            return true
        }

        if retriedCount > self.RetryPolicyMaximumRetryCount {
            return false
        }

        if error {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
                return true
            }
        }

        if response.statusCode == 408 || response.statusCode == 503 {
            return true
        }

        return false
    }

    // NSURLSessionTaskDelegate
    func URLSession(session: NSURLSession!, task: NSURLSessionTask!,
    didCompleteWithError error: NSError!) {
        if let indicator = self.networkActivityIndicator {
            indicator.decrease()
        }

        var cycle: Cycle! = self.cycleForTask(task)

        cycle.response.core = task.response as? NSHTTPURLResponse
        cycle.response.timestamp = NSDate()

        if error {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                self.delegateQueue.addOperationWithBlock {
                    if !cycle.explicitlyCanceling {
                        cycle.completionHandler(cycle: cycle, error: error)
                    }
                }
                self.removeCycle(cycle)
                return
            }
        }

        var retry = false
        if let value = self.delegate?.sessionShouldRetryCycle?(self, cycle: cycle,
        error: error) {
            retry = value
            println("\(value)")

        } else {
            retry = self.shouldRetry(cycle.solicited, retriedCount: cycle.retriedCount,
                request: cycle.request, response: cycle.response,
                error: error)
        }

        if retry {
            ++cycle.retriedCount
            dispatch_after(self.retryDelay, self.delegateQueue.underlyingQueue) {
                cycle.restart()
            }
            return
        }

        var statusFailure = false
        if let value = self.delegate?.sessionShouldTreatStatusCodeAsFailure?(self,
        status: cycle.response.statusCode!) {
            statusFailure = value
        } else {
            if cycle.response.statusCode >= 400 {
                statusFailure = true
            }
        }
        if statusFailure {
            var error = NSError(domain: CycleErrorDomain,
                                code: CycleErrorCode.StatusCodeSeemsToHaveErred.toRaw(),
                                userInfo: nil)
            self.cycleDidFinish(cycle, error: error)
            return
        }

        if error {
            self.cycleDidFinish(cycle, error: error)
            return
        }

        self.workerQueue.addOperationWithBlock {
            var error: NSError?
            for i in cycle.responseProcessors {
                if !i.processResponse(cycle.response, error: &error) {
                    break
                }
            }
            self.cycleDidFinish(cycle, error: error)
        }

    }

    func URLSession(session: NSURLSession!, task: NSURLSessionTask!,
    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64) {
        var cycle = self.cycleForTask(task)
        assert(cycle)

        cycle?.didSendBodyDataHandler?(cycle: cycle!, bytesSent: bytesSent,
                                       totalBytesSent: totalBytesSent,
                                       totalBytesExpectedToSend: totalBytesExpectedToSend)
    }


    func URLSession(session: NSURLSession!, task: NSURLSessionTask!,
    didReceiveChallenge challenge: NSURLAuthenticationChallenge!,
    completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void)!) {
        var cycle = self.cycleForTask(task)!

        var handlers = cycle.authentications
        var count = 0
        for handler in handlers {
            if handler.canHandleAuthenticationChallenge(challenge, cycle: cycle) {
                ++count
                var action = handler.actionForAuthenticationChallenge(challenge, cycle: cycle)
                handler.performAction(action, challenge: challenge,
                                      completionHandler: completionHandler,
                                      cycle: cycle)
            }
        }
        if count == 0 {
            completionHandler(NSURLSessionAuthChallengeDisposition.PerformDefaultHandling, nil)
        }
    }

    // NSURLSessionDataDelegate
    func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!,
    didReceiveData data: NSData!) {
        var cycle = self.cycleForTask(dataTask)!

        cycle.response.appendData(data)
    }

    // NSURLSessionDownloadDelegate
    func URLSession(session: NSURLSession!, downloadTask: NSURLSessionDownloadTask!,
    didFinishDownloadingToURL location: NSURL!) {
        var cycle = self.cycleForTask(downloadTask)!

        cycle.downloadFileHandler?(cycle: cycle, location: location)
    }

    func URLSession(session: NSURLSession!, downloadTask: NSURLSessionDownloadTask!,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64) {
        var cycle = self.cycleForTask(downloadTask)!

        cycle.didWriteDataHandler?(cycle: cycle, bytesWritten: bytesWritten,
                                   totalBytesWritten: totalBytesWritten,
                                   totalBytesExpectedToWrite: totalBytesExpectedToWrite);
    }

    func cycleDidFinish(cycle: Cycle, error: NSError?) {
        self.delegateQueue.addOperationWithBlock {
            cycle.completionHandler(cycle: cycle, error: error)
            self.delegateQueue.addOperationWithBlock {
                self.removeCycle(cycle)
            }
        }
    }

    func cycleDidStart(cycle: Cycle) {
        if let indicator = self.networkActivityIndicator {
            indicator.increase()
        }
    }

// ---
/*!
 * @abstract 
 * Cancel an array of HTTP request operations.
 *
 * @param cycles 
 * An array of Cycle objects to cancel.
 *
 * @param explicitly 
 * Indicate if the operations are cancelled explicitly. The value will be 
 * stored in each Cycle's property explicitlyCanceling. Your app can use
 * this value for cancellation interface.
 */
    func cancelCycles(cycles: [Cycle], explicitly: Bool) {
        for cycle in cycles {
            cycle.explicitlyCanceling = explicitly
            cycle.core!.cancel()
        }
    }

/*!
 * @discussion 
 * Cancel all outstanding tasks and then invalidates the session object.
 * Once invalidated, references to the delegate and callback objects are broken.
 * The session object cannot be reused.
 *
 * @param explicitly 
 * Indicate if the operations are cancelled explicitly.
 */
    func invalidateAndCancel(explicitly: Bool) {
        for cycle in cycles {
            cycle.explicitlyCanceling = explicitly
        }
        self.core.invalidateAndCancel()
    }
    
/*!
 * @discussion 
 * Invalidate the session, allowing any outstanding tasks to finish. This method 
 * returns immediately without waiting for tasks to finish. Once a session is 
 * invalidated, new tasks cannot be created in the session, but existing tasks 
 * continue until completion. After the last task finishes and the session makes 
 * the last delegate call, references to the delegate and callback objects are 
 * broken. Session objects cannot be reused.
 *
 * @param explicitly 
 * Indicate if the operations are cancelled explicitly.
 */
    func finishTaskAndInvalidate(explicitly: Bool) {
        for cycle in cycles {
            cycle.explicitlyCanceling = explicitly
        }
        self.core.finishTasksAndInvalidate()
    }

// -- Preserved
    func setPreservedHTTPHeaderField(field: String, value: String) {
        self.preservedHTTPHeaders[field.lowercaseString] = value
    }

    func setPreservedHTTPQueryParameter(key: String, value: [String]) {
        self.preservedHTTPQueryParameters[key.lowercaseString] = value
    }

    func dataForPreservedState(error: NSErrorPointer) -> NSData {
        var objects = [self.preservedHTTPHeaders, self.preservedHTTPQueryParameters]
        var keys = [PreservedHTTPHeadersKey, PreservedHTTPQueryParametersKey]
        var dict = NSDictionary(objects: objects, forKeys: keys)
        var data = NSPropertyListSerialization.dataWithPropertyList(dict,
                    format: .BinaryFormat_v1_0, options: 0, error:error)

        return data
    }

    func loadPreservedStateFromData(data: NSData, error: NSErrorPointer) -> Bool {
        var options = NSPropertyListReadOptions(NSPropertyListMutabilityOptions.MutableContainersAndLeaves.toRaw()) // TODO: improve me
        if let dict = NSPropertyListSerialization.propertyListWithData(data,
        options:options, format: nil, error: error) as? NSDictionary {
            if let headers = dict[PreservedHTTPHeadersKey] as? Dictionary<String, String> {
                self.preservedHTTPHeaders = headers
            }
            if let parameters = dict[PreservedHTTPQueryParametersKey] as? Dictionary<String, [String]> {
                self.preservedHTTPQueryParameters = parameters
            }
        }

        return true
    }

    func applyPreservedStateToRequest(request: Request) {
        // headers
        for (key, value) in self.preservedHTTPHeaders {
            request.core.setValue(value, forHTTPHeaderField: key)
        }

        // parameters
        if self.preservedHTTPQueryParameters.count > 0 {
            var URLString = request.core.URL.absoluteString
            URLString = MergeParametersToURL(URLString, self.preservedHTTPQueryParameters)
            if let URL = NSURL.URLWithString(URLString) {
                var URLString = request.core.URL.absoluteString
                request.core.URL = URL
            }
        }
    }

}


