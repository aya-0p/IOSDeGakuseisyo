#import "StudentCardReader.h"

#import "StudentCard.h"

#include "FeliCaPollingResponse.hpp"

#import <CoreNFC/CoreNFC.h>

static NSString *const kAuthorizedReaderErrorDomain =
    @"org.hoshitsugi.iosdegakuseisyo.card-reader";

static NSError *ReaderError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:kAuthorizedReaderErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@interface StudentCardReader () <NFCTagReaderSessionDelegate>
@property(nonatomic, strong) NFCTagReaderSession *session;
@property(nonatomic, copy) StudentCardReaderCompletion completion;
@property(nonatomic, assign) BOOL finished;
@end

@implementation StudentCardReader

- (void)startWithCompletion:(StudentCardReaderCompletion)completion {
    if (self.session != nil || self.completion != nil) {
        if (completion != nil)
            completion(nil, ReaderError(6, @"NFC読み取りはすでに開始しています。"));
        return;
    }
    self.completion = completion;
    self.finished = NO;
    if (![NFCReaderSession readingAvailable]) {
        [self finishWithCard:nil
                      error:ReaderError(1, @"この端末ではNFCを読み取れません。")];
        return;
    }
    self.session = [[NFCTagReaderSession alloc]
        initWithPollingOption:NFCPollingISO18092
                     delegate:self queue:nil];
    self.session.alertMessage =
        @"学生証をiPhone上部に近づけてください。";
    [self.session beginSession];
}

- (void)finishWithCard:(StudentCard *_Nullable)card
                  error:(NSError *_Nullable)error {
    @synchronized(self) {
        if (self.finished) return;
        self.finished = YES;
    }
    StudentCardReaderCompletion completion = self.completion;
    self.completion = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion != nil) completion(card, error);
    });
}

- (void)fail:(NFCTagReaderSession *)session
     message:(NSString *)message
       error:(NSError *)error {
    [session invalidateSessionWithErrorMessage:message];
    [self finishWithCard:nil error:error];
}

- (void)tagReaderSession:(NFCTagReaderSession *)session
    didInvalidateWithError:(NSError *)error {
    self.session = nil;
    if (self.finished) return;
    if ([error.domain isEqualToString:NFCErrorDomain] &&
        error.code == NFCReaderSessionInvalidationErrorUserCanceled) {
        [self finishWithCard:nil error:nil];
        return;
    }
    [self finishWithCard:nil error:error];
}

- (void)tagReaderSession:(NFCTagReaderSession *)session
           didDetectTags:(NSArray<__kindof id<NFCTag>> *)tags {
    if (tags.count != 1) {
        session.alertMessage = @"カードは1枚だけ近づけてください。";
        [session restartPolling];
        return;
    }
    id<NFCTag> tag = tags.firstObject;
    id<NFCFeliCaTag> felica = [tag asNFCFeliCaTag];
    const uint8_t systemBytes[2] = {
        static_cast<uint8_t>(StudentCardSystemCode >> 8),
        static_cast<uint8_t>(StudentCardSystemCode & 0xff),
    };
    NSData *systemCode = [NSData dataWithBytes:systemBytes length:2];
    if (felica == nil || ![felica.currentSystemCode isEqualToData:systemCode] ||
        felica.currentIDm.length != 8) {
        [self fail:session message:@"FeliCa学生証ではありません。"
              error:ReaderError(2, @"048BのFeliCa学生証を検出できませんでした。")];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [session connectToTag:tag completionHandler:^(NSError *connectError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || self.finished) return;
        if (connectError != nil) {
            [self fail:session message:@"カードに接続できませんでした。"
                 error:connectError];
            return;
        }
        const uint8_t serviceBytes[2] = {
            static_cast<uint8_t>(StudentCardServiceCode & 0xff),
            static_cast<uint8_t>(StudentCardServiceCode >> 8),
        };
        NSData *service = [NSData dataWithBytes:serviceBytes length:2];
        NSMutableArray<NSData *> *blockList =
            [NSMutableArray arrayWithCapacity:StudentCardBlockCount];
        for (uint8_t block = 0; block < StudentCardBlockCount; ++block) {
            uint8_t descriptor[2] = {0x80, block};
            [blockList addObject:[NSData dataWithBytes:descriptor length:2]];
        }
        [felica readWithoutEncryptionWithServiceCodeList:@[service]
                                               blockList:blockList
                                       completionHandler:^(NSInteger statusFlag1,
                                                           NSInteger statusFlag2,
                                                           NSArray<NSData *> *blocks,
                                                           NSError *readError) {
            if (self.finished) return;
            if (readError != nil || statusFlag1 != 0 || statusFlag2 != 0) {
                [self fail:session message:@"学生証を読み取れませんでした。"
                     error:readError ?: ReaderError(3, @"サービス応答がエラーでした。")];
                return;
            }
            if (blocks.count != StudentCardBlockCount) {
                [self fail:session message:@"ブロック数が正しくありません。"
                     error:ReaderError(4, @"4ブロックを読み取れませんでした。")];
                return;
            }

            NSData *idm = felica.currentIDm;
            // Core NFC inserts the FeliCa LEN and CRC fields. The packet here
            // therefore begins with the Polling command code, not LEN.
            [felica sendFeliCaCommandPacket:[NSData dataWithBytes:(uint8_t[]){
                0x00,
                static_cast<uint8_t>(StudentCardSystemCode >> 8),
                static_cast<uint8_t>(StudentCardSystemCode & 0xff),
                0x01,
                0x00,
            } length:5] completionHandler:^(NSData *pollResponse, NSError *pollError) {
                if (self.finished) return;
                if (pollError != nil || pollResponse.length < 17) {
                    [self fail:session message:@"PMmを読み取れませんでした。"
                         error:pollError ?: ReaderError(
                             7, @"学生証のPolling応答が正しくありません。")];
                    return;
                }
                const uint8_t *p =
                    static_cast<const uint8_t *>(pollResponse.bytes);
                uint8_t pmmTailBytes[6] = {};
                if (!nfcf::ExtractPollingPMmTail(
                        p, pollResponse.length,
                        static_cast<const uint8_t *>(idm.bytes),
                        pmmTailBytes)) {
                    [self fail:session message:@"PMmを読み取れませんでした。"
                         error:ReaderError(
                             7, @"Polling応答のIDmまたは長さが一致しません。")];
                    return;
                }
                NSData *pmmTail = [NSData dataWithBytes:pmmTailBytes
                                                  length:sizeof(pmmTailBytes)];

                NSError *cardError = nil;
                StudentCard *card = [[StudentCard alloc]
                    initWithIDm:idm pmmTail:pmmTail blocks:blocks error:&cardError];
                if (card == nil) {
                    [self fail:session message:@"カードの内容を処理できませんでした。"
                         error:cardError ?: ReaderError(5, @"カード形式が一致しません。")];
                    return;
                }
                session.alertMessage = @"学生証を読み取りました。";
                [session invalidateSession];
                [self finishWithCard:card error:nil];
            }];
        }];
    }];
}

@end
