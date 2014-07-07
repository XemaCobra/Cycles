//
//  Request.swift
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

/*!
 * @abstract 
 * This class represents a HTTP request.
 */
class Request {
/*!
 * @abstract 
 * The NSMutableURLRequest represents the primary request information.
 */
    var core: NSMutableURLRequest

/*!
 * @discussion 
 * The object represents the request data. The Processor objects will use this 
 * object to build HTTP headers and body.
 */
    var object: AnyObject?

/*!
 * @abstract 
 * The NSDate stores the time the request is sent.
 */
    var timestamp: NSDate?

/*!
 * @discussion 
 * The NSData to send as HTTP body.
 */
    var data: NSData? {
    get {
        if let body = self.core.HTTPBody {
            return body
        }
        return nil
    }

    set {
        self.core.HTTPBody = newValue
    }
    }

/*!
 * @abstract 
 * Initialize a Request object
 *
 * @param URLRequest 
 * The NSURLRequest represents the primary request information.
 */
    init(core: NSURLRequest) {
        self.core = core.mutableCopy() as NSMutableURLRequest
    }
}