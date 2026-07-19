#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CardBackupCodec : NSObject

+ (NSUInteger)maximumBackupSize;
+ (nullable NSData *)encodeRecords:(NSArray<NSData *> *)records
                     selectedIndex:(NSInteger)selectedIndex
                             error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)decodeBackup:(NSData *)data
             records:(NSArray<NSData *> *_Nullable *_Nonnull)records
       selectedIndex:(NSInteger *)selectedIndex
               error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
