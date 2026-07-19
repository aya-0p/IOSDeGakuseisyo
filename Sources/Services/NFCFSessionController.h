#import <Foundation/Foundation.h>

@class BackendResult;
@class StudentCard;

NS_ASSUME_NONNULL_BEGIN

typedef void (^NFCFSessionCompletion)(BackendResult *result);

@interface NFCFSessionController : NSObject

- (void)refreshRecoveringIfActive:(BOOL)recover
                        completion:(NFCFSessionCompletion)completion;
- (void)startWithCard:(StudentCard *)card
           completion:(NFCFSessionCompletion)completion;
- (void)stopWithCompletion:(NFCFSessionCompletion)completion;
- (void)loadLogsWithCompletion:(NFCFSessionCompletion)completion;
- (NSString *)diagnosticLog;

@end

NS_ASSUME_NONNULL_END
