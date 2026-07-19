#import <Foundation/Foundation.h>

#import "StudentCard.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

int main() {
    @autoreleasepool {
        const uint8_t idmBytes[8] = {1, 2, 3, 4, 5, 6, 7, 8};
        const uint8_t pmmBytes[6] = {9, 10, 11, 12, 13, 14};
        NSData *idm = [NSData dataWithBytes:idmBytes length:sizeof(idmBytes)];
        NSData *pmm = [NSData dataWithBytes:pmmBytes length:sizeof(pmmBytes)];
        NSMutableArray<NSData *> *blocks = [NSMutableArray array];
        for (NSUInteger index = 0; index < StudentCardBlockCount; ++index) {
            uint8_t bytes[16] = {};
            memset(bytes, (int)(index + 1), sizeof(bytes));
            [blocks addObject:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
        }

        NSError *error = nil;
        StudentCard *card = [[StudentCard alloc] initWithIDm:idm
            pmmTail:pmm blocks:blocks error:&error];
        assert(card != nil && error == nil);
        NSData *record = [card recordData:&error];
        assert(record.length == 99 && error == nil);
        assert(memcmp(record.bytes, "NFCFPROF", 8) == 0);

        StudentCard *decoded = [StudentCard cardWithRecordData:record
                                                       error:&error];
        assert(decoded != nil && error == nil);
        assert([[decoded recordData:&error] isEqualToData:record]);

        NSMutableData *corrupted = [record mutableCopy];
        static_cast<uint8_t *>(corrupted.mutableBytes)[20] ^= 1;
        error = nil;
        assert([StudentCard cardWithRecordData:corrupted error:&error] == nil);
        assert(error != nil);
    }
    return 0;
}
