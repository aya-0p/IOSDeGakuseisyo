#import <Foundation/Foundation.h>

@class BackendResult;

NS_ASSUME_NONNULL_BEGIN

@interface BackendClient : NSObject

// This is intentionally synchronous so multi-command transactions can run on
// one private serial queue. UI code must use NFCFSessionController instead.
- (BackendResult *)runCommandWithArguments:(NSArray<NSString *> *)arguments;
- (NSString *)diagnosticLog;

@end

NS_ASSUME_NONNULL_END
