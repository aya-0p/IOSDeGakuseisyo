#import <Foundation/Foundation.h>

#import "CardBackupCodec.h"

#include <assert.h>
#include <string.h>

int main() {
    @autoreleasepool {
        NSMutableData *first = [NSMutableData dataWithLength:99];
        NSMutableData *second = [NSMutableData dataWithLength:99];
        memset(first.mutableBytes, 0x11, first.length);
        memset(second.mutableBytes, 0x22, second.length);
        NSError *error = nil;
        NSData *backup = [CardBackupCodec encodeRecords:@[first, second]
            selectedIndex:1 error:&error];
        assert(backup != nil && error == nil);

        NSArray<NSData *> *records = nil;
        NSInteger selected = -1;
        assert([CardBackupCodec decodeBackup:backup records:&records
                               selectedIndex:&selected error:&error]);
        assert(records.count == 2 && selected == 1);
        assert([records[0] isEqual:first] && [records[1] isEqual:second]);

        NSMutableData *oversized = [NSMutableData dataWithLength:1024 * 1024 + 1];
        assert([CardBackupCodec maximumBackupSize] == 1024 * 1024);
        assert(![CardBackupCodec decodeBackup:oversized records:&records
                                selectedIndex:&selected error:&error]);

        NSData *arrayRoot = [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
        error = nil;
        assert(![CardBackupCodec decodeBackup:arrayRoot records:&records
                                selectedIndex:&selected error:&error]);
        assert(error != nil);

        NSString *recordBase64 = [first base64EncodedStringWithOptions:0];
        NSDictionary *unsupportedRoot = @{
            @"format": @"unsupported",
            @"version": @1,
            @"selectedIndex": @0,
            @"records": @[recordBase64],
        };
        NSData *unsupported = [NSJSONSerialization
            dataWithJSONObject:unsupportedRoot options:0 error:nil];
        error = nil;
        assert(![CardBackupCodec decodeBackup:unsupported records:&records
                                selectedIndex:&selected error:&error]);
        assert(error != nil);

        NSData *shortRecord = [NSMutableData dataWithLength:96];
        NSDictionary *invalidRecordRoot = @{
            @"format": @"ios-de-gakuseisyo-backup",
            @"version": @1,
            @"selectedIndex": @0,
            @"records": @[[shortRecord base64EncodedStringWithOptions:0]],
        };
        NSData *invalidRecord = [NSJSONSerialization
            dataWithJSONObject:invalidRecordRoot options:0 error:nil];
        error = nil;
        assert(![CardBackupCodec decodeBackup:invalidRecord records:&records
                                selectedIndex:&selected error:&error]);
        assert(error != nil);

        NSMutableArray *tooMany = [NSMutableArray array];
        for (NSUInteger index = 0; index < 65; ++index)
            [tooMany addObject:first];
        assert([CardBackupCodec encodeRecords:tooMany selectedIndex:0
                                         error:&error] == nil);
    }
    return 0;
}
