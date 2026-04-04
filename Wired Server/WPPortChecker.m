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
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

@implementation WPPortChecker

#pragma mark -

- (void)setDelegate:(id)newDelegate {
    delegate = newDelegate;
}

- (id)delegate {
    return delegate;
}

#pragma mark -

// Performs a non-blocking TCP connect to 127.0.0.1:port with a 5-second
// timeout. Returns Open if wired is listening, Closed if the port is not
// in use, Filtered on timeout, or Failed on any socket error.
- (WPPortCheckerStatus)_checkPort:(NSUInteger)port {
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0)
        return WPPortCheckerFailed;

    // Switch to non-blocking so connect() returns immediately
    int flags = fcntl(sockfd, F_GETFL, 0);
    if (flags < 0 || fcntl(sockfd, F_SETFL, flags | O_NONBLOCK) < 0) {
        close(sockfd);
        return WPPortCheckerFailed;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons((uint16_t)port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // 127.0.0.1

    int result = connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));

    if (result == 0) {
        // Immediate success (possible on loopback)
        close(sockfd);
        return WPPortCheckerOpen;
    }
    if (errno == ECONNREFUSED) {
        close(sockfd);
        return WPPortCheckerClosed;
    }
    if (errno != EINPROGRESS) {
        close(sockfd);
        return WPPortCheckerFailed;
    }

    // Wait up to 5 seconds for the connection to complete
    fd_set writeSet;
    FD_ZERO(&writeSet);
    FD_SET(sockfd, &writeSet);
    struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };

    result = select(sockfd + 1, NULL, &writeSet, NULL, &tv);

    if (result == 0) {          // Timeout
        close(sockfd);
        return WPPortCheckerFiltered;
    }
    if (result < 0) {
        close(sockfd);
        return WPPortCheckerFailed;
    }

    // select() returned ready — check whether connect() succeeded
    int soError = 0;
    socklen_t soErrorLen = sizeof(soError);
    getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &soError, &soErrorLen);
    close(sockfd);

    if (soError == 0)             return WPPortCheckerOpen;
    if (soError == ECONNREFUSED)  return WPPortCheckerClosed;
    return WPPortCheckerFiltered;
}

- (void)checkStatusForPort:(NSUInteger)port {
    _port = port;

    // Run the blocking socket check on a background queue and
    // deliver the result on the main queue
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        WPPortCheckerStatus status = [self _checkPort:port];

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(portChecker:didReceiveStatus:forPort:)])
                [delegate portChecker:self didReceiveStatus:status forPort:port];
        });
    });
}

@end
