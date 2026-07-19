#import <Foundation/Foundation.h>

#import "BackendResult.h"

#include <assert.h>

int main() {
    @autoreleasepool {
        NSString *output =
            @"diagnostic line\n"
             "NFCF_JSON:{\"schemaVersion\":1,\"success\":true,"
             "\"command\":\"status\",\"state\":\"active\","
             "\"routing\":\"active\",\"profile\":\"loaded\","
             "\"code\":\"ok\",\"message\":\"ready\","
             "\"recordFingerprint\":\"abcdef\"}\n";
        BackendResult *result = [[BackendResult alloc]
            initWithOutput:output exitCode:0];
        assert(result.isSuccess);
        assert([result.command isEqual:@"status"]);
        assert([result.routing isEqual:@"active"]);
        assert([result.profile isEqual:@"loaded"]);
        assert([result.recordFingerprint isEqual:@"ABCDEF"]);

        BackendResult *failed = [[BackendResult alloc]
            initWithOutput:@"not-json" exitCode:7];
        assert(!failed.isSuccess);
        assert([failed.state isEqual:@"unknown"]);

        BackendResult *combined = [result resultByPrependingOutput:@"first"];
        assert(combined.isSuccess);
        assert([combined.rawOutput hasPrefix:@"first\n"]);
    }
    return 0;
}
