#import "NFCFSessionController.h"

#import "BackendClient.h"
#import "BackendResult.h"
#import "StudentCard.h"

@interface NFCFSessionController ()
@property(nonatomic, strong) BackendClient *client;
@property(nonatomic) dispatch_queue_t queue;
@end

@implementation NFCFSessionController

- (instancetype)init {
    self = [super init];
    if (self) {
        _client = [[BackendClient alloc] init];
        _queue = dispatch_queue_create(
            "org.hoshitsugi.iosdegakuseisyo.backend", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)perform:(BackendResult *(^)(void))work
      completion:(NFCFSessionCompletion)completion {
    dispatch_async(self.queue, ^{
        BackendResult *result = work();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) completion(result);
        });
    });
}

- (void)refreshRecoveringIfActive:(BOOL)recover
                        completion:(NFCFSessionCompletion)completion {
    [self perform:^BackendResult *{
        BackendResult *recovery = recover
            ? [self.client runCommandWithArguments:@[@"recover"]] : nil;
        BackendResult *status =
            [self.client runCommandWithArguments:@[@"status"]];
        return recovery == nil ? status
            : [status resultByPrependingOutput:recovery.rawOutput];
    } completion:completion];
}

- (void)startWithCard:(StudentCard *)card
           completion:(NFCFSessionCompletion)completion {
    [self perform:^BackendResult *{
        NSError *error = nil;
        if (![card writeTemporaryRecord:&error]) {
            return [[BackendResult alloc]
                initWithOutput:error.localizedDescription ?:
                    @"一時学生証を書き込めませんでした。"
                       exitCode:1];
        }
        BackendResult *apply =
            [self.client runCommandWithArguments:@[@"profile", @"apply"]];
        if (!apply.isSuccess) return apply;
        BackendResult *start = [self.client
            runCommandWithArguments:@[@"start"]];
        return [start resultByPrependingOutput:apply.rawOutput];
    } completion:completion];
}

- (void)stopWithCompletion:(NFCFSessionCompletion)completion {
    [self perform:^BackendResult *{
        return [self.client runCommandWithArguments:@[@"stop"]];
    } completion:completion];
}

- (void)loadLogsWithCompletion:(NFCFSessionCompletion)completion {
    [self perform:^BackendResult *{
        return [self.client runCommandWithArguments:@[@"logs"]];
    } completion:completion];
}

- (NSString *)diagnosticLog {
    return self.client.diagnosticLog;
}

@end
