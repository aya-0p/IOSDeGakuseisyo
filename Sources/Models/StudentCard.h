#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const uint16_t StudentCardSystemCode;
FOUNDATION_EXPORT const uint16_t StudentCardServiceCode;
FOUNDATION_EXPORT const NSUInteger StudentCardBlockCount;

@interface StudentCard : NSObject

@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, copy, readonly) NSString *detailText;
@property(nonatomic, copy, readonly) NSString *maskedIDm;
@property(nonatomic, copy, readonly) NSString *recordFingerprint;

- (nullable instancetype)initWithIDm:(NSData *)idm
                             pmmTail:(NSData *)pmmTail
                               blocks:(NSArray<NSData *> *)blocks
                                error:(NSError *_Nullable *_Nullable)error;

- (BOOL)writeTemporaryRecord:(NSError *_Nullable *_Nullable)error;
- (nullable NSData *)recordData:(NSError *_Nullable *_Nullable)error;
+ (nullable instancetype)cardWithRecordData:(NSData *)data
                                      error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
