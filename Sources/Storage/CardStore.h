#import <Foundation/Foundation.h>

@class StudentCard;

NS_ASSUME_NONNULL_BEGIN

@interface CardStore : NSObject

@property(nonatomic, copy, readonly) NSArray<StudentCard *> *cards;
@property(nonatomic, assign, readonly) NSInteger selectedIndex;
@property(nonatomic, strong, readonly, nullable) StudentCard *selectedCard;

- (BOOL)addCardAndSelect:(StudentCard *)card
                   error:(NSError *_Nullable *_Nullable)error;
- (BOOL)selectCardAtIndex:(NSUInteger)index
                    error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeCardAtIndex:(NSUInteger)index
                    error:(NSError *_Nullable *_Nullable)error;
- (BOOL)save:(NSError *_Nullable *_Nullable)error;
- (nullable NSData *)exportBackup:(NSError *_Nullable *_Nullable)error;
- (BOOL)restoreBackup:(NSData *)data error:(NSError *_Nullable *_Nullable)error;
- (BOOL)eraseAll:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
