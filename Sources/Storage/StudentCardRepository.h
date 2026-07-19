#import <Foundation/Foundation.h>

@class StudentCard;

NS_ASSUME_NONNULL_BEGIN

@interface StudentCardRepository : NSObject

+ (nullable NSMutableArray<StudentCard *> *)loadAllCards;
+ (NSInteger)savedSelectedIndex;
+ (BOOL)saveCards:(NSArray<StudentCard *> *)cards
     selectedIndex:(NSInteger)selectedIndex
             error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)deleteStorageKeys:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
