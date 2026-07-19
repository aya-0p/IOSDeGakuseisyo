#import "CardBackupCodec.h"

static const NSUInteger kMaximumCardCount = 64;
static const NSUInteger kMaximumBackupSize = 1024 * 1024;
static const NSUInteger kProfileRecordSize = 99;
static const NSUInteger kMaximumEncodedRecordLength = 132;

static NSError *BackupError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"org.hoshitsugi.iosdegakuseisyo.backup"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation CardBackupCodec

+ (NSUInteger)maximumBackupSize {
    return kMaximumBackupSize;
}

+ (NSData *)encodeRecords:(NSArray<NSData *> *)records
             selectedIndex:(NSInteger)selectedIndex
                     error:(NSError **)error {
    if (records.count == 0 || records.count > kMaximumCardCount ||
        selectedIndex < 0 || selectedIndex >= (NSInteger)records.count) {
        if (error != NULL)
            *error = BackupError(1, @"書き出す学生証の数または選択位置が正しくありません。");
        return nil;
    }
    NSMutableArray *encoded = [NSMutableArray arrayWithCapacity:records.count];
    for (NSData *record in records) {
        if (![record isKindOfClass:[NSData class]] ||
            record.length != kProfileRecordSize) {
            if (error != NULL)
                *error = BackupError(2, @"学生証データの長さが正しくありません。");
            return nil;
        }
        [encoded addObject:[record base64EncodedStringWithOptions:0]];
    }
    NSDictionary *root = @{
        @"format": @"ios-de-gakuseisyo-backup",
        @"version": @1,
        @"selectedIndex": @(selectedIndex),
        @"records": encoded,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:root
        options:NSJSONWritingPrettyPrinted error:error];
    if (data.length > kMaximumBackupSize) {
        if (error != NULL)
            *error = BackupError(3, @"バックアップが1 MBを超えています。");
        return nil;
    }
    return data;
}

+ (BOOL)decodeBackup:(NSData *)data records:(NSArray<NSData *> **)records
       selectedIndex:(NSInteger *)selectedIndex error:(NSError **)error {
    if (data.length == 0 || data.length > kMaximumBackupSize) {
        if (error != NULL)
            *error = BackupError(3, @"バックアップは1 MB以下である必要があります。");
        return NO;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    NSDictionary *root = [object isKindOfClass:[NSDictionary class]]
        ? object : nil;
    if (root == nil) {
        if (error != NULL && *error == nil)
            *error = BackupError(4, @"バックアップ形式が正しくありません。");
        return NO;
    }
    NSString *format = root[@"format"];
    NSArray *encoded = root[@"records"];
    if (![format isEqual:@"ios-de-gakuseisyo-backup"] ||
        ![root[@"version"] isEqual:@1] ||
        ![encoded isKindOfClass:[NSArray class]] || encoded.count == 0 ||
        encoded.count > kMaximumCardCount) {
        if (error != NULL)
            *error = BackupError(4, @"バックアップ形式が正しくありません。");
        return NO;
    }
    NSMutableArray<NSData *> *decoded =
        [NSMutableArray arrayWithCapacity:encoded.count];
    for (id value in encoded) {
        if (![value isKindOfClass:[NSString class]] ||
            [value length] > kMaximumEncodedRecordLength) {
            if (error != NULL)
                *error = BackupError(5, @"バックアップ内の学生証が壊れています。");
            return NO;
        }
        NSData *record = [[NSData alloc]
            initWithBase64EncodedString:value options:0];
        if (record.length != kProfileRecordSize) {
            if (error != NULL)
                *error = BackupError(5, @"バックアップ内の学生証が壊れています。");
            return NO;
        }
        [decoded addObject:record];
    }
    NSInteger selected = [root[@"selectedIndex"] isKindOfClass:[NSNumber class]]
        ? [root[@"selectedIndex"] integerValue] : 0;
    if (selected < 0 || selected >= (NSInteger)decoded.count) selected = 0;
    *records = decoded;
    *selectedIndex = selected;
    return YES;
}

@end
