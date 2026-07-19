#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BackendResult : NSObject

@property(nonatomic, copy, readonly) NSString *rawOutput;
@property(nonatomic, assign, readonly) int exitCode;
@property(nonatomic, assign, readonly, getter=isSuccess) BOOL success;
@property(nonatomic, copy, readonly) NSString *command;
@property(nonatomic, copy, readonly) NSString *state;
@property(nonatomic, copy, readonly) NSString *routing;
@property(nonatomic, copy, readonly) NSString *profile;
@property(nonatomic, copy, readonly) NSString *code;
@property(nonatomic, copy, readonly) NSString *message;
@property(nonatomic, copy, readonly) NSString *recordFingerprint;

- (instancetype)initWithOutput:(NSString *)output exitCode:(int)exitCode;
- (BackendResult *)resultByPrependingOutput:(NSString *)output;

@end

NS_ASSUME_NONNULL_END
