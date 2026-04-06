/* $Id$ */

/*
 *  Copyright (c) 2009 Axel Andersson
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#import "WPPortChecker.h"

@implementation WPPortChecker

#pragma mark -

- (void)setDelegate:(id)newDelegate {
    delegate = newDelegate;
}

- (id)delegate {
    return delegate;
}

#pragma mark -

// Ask canyouseeme.org to probe the port from the internet.
// canyouseeme.org uses the requesting machine's public IP automatically —
// no need to pre-resolve the public IP via a separate service.
//
// POST body: action=canyouseeme&port=PORT
// Success:   response HTML contains "<b>Success:</b>"
// Closed:    response HTML contains "<b>Error:</b>"
- (void)checkStatusForPort:(NSUInteger)port {
    _port = port;
    id<NSObject> retainedDelegate = (id<NSObject>)delegate;

    void (^report)(WPPortCheckerStatus) = ^(WPPortCheckerStatus s) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([retainedDelegate respondsToSelector:
                    @selector(portChecker:didReceiveStatus:forPort:)])
                [(id)retainedDelegate portChecker:self
                                didReceiveStatus:s
                                         forPort:port];
        });
    };

    NSString *body = [NSString stringWithFormat:@"action=canyouseeme&port=%lu",
        (unsigned long)port];
    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:@"https://canyouseeme.org/"]
           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
       timeoutInterval:30.0];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded"
         forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

    [[[NSURLSession sharedSession]
        dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {

        if (!err && data) {
            NSString *html = [[[NSString alloc] initWithData:data
                encoding:NSUTF8StringEncoding] autorelease];
            if ([html rangeOfString:@"<b>Success:</b>"].location != NSNotFound) {
                report(WPPortCheckerOpen); return;
            }
            if ([html rangeOfString:@"<b>Error:</b>"].location != NSNotFound) {
                report(WPPortCheckerClosed); return;
            }
        }

        report(WPPortCheckerFailed);

    }] resume];
}

@end
