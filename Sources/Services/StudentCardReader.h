#import <Foundation/Foundation.h>

@class StudentCard;

NS_ASSUME_NONNULL_BEGIN

typedef void (^StudentCardReaderCompletion)(
    StudentCard *_Nullable card, NSError *_Nullable error);

@interface StudentCardReader : NSObject

- (void)startWithCompletion:(StudentCardReaderCompletion)completion;

@end

NS_ASSUME_NONNULL_END
