#import "StudentCard.h"

#include "NFCFProfileRecord.hpp"

#import <CommonCrypto/CommonDigest.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const kStudentCardErrorDomain =
    @"org.hoshitsugi.iosdegakuseisyo.card";
static NSString *const kBackendStateDirectory =
    @"/var/mobile/Library/Caches/org.hoshitsugi.iosnfcfcardemulation";
static NSString *const kTemporaryProfilePath =
    @"/var/mobile/Library/Caches/org.hoshitsugi.iosnfcfcardemulation/profile.record";

const uint16_t StudentCardSystemCode = 0x048b;
const uint16_t StudentCardServiceCode = 0x200b;
const NSUInteger StudentCardBlockCount = 4;

static void SecureZero(void *bytes, size_t length) {
    volatile uint8_t *cursor = static_cast<volatile uint8_t *>(bytes);
    while (cursor != nullptr && length-- != 0) *cursor++ = 0;
}

static NSError *CardError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:kStudentCardErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL DecodeStudentProfile(NSData *data, nfcf::Profile *profile) {
    if (data.length != nfcf::kProfileRecordEncodedSize ||
        profile == nullptr) return NO;
    nfcf::ProfileRecord record = {};
    BOOL decoded = nfcf::DecodeProfileRecordBytes(
                       static_cast<const uint8_t *>(data.bytes), data.length,
                       &record) &&
                   nfcf::DecodeProfileRecord(record, profile);
    SecureZero(&record, sizeof(record));
    if (!decoded) return NO;
    return profile->system_code == StudentCardSystemCode &&
           profile->service_code == StudentCardServiceCode &&
           profile->block_count == StudentCardBlockCount;
}

static NSString *StringFromBlock(NSData *block, NSStringEncoding encoding) {
    const uint8_t *bytes = static_cast<const uint8_t *>(block.bytes);
    NSUInteger length = block.length;
    while (length != 0 && bytes[length - 1] == 0) --length;
    NSData *trimmed = [NSData dataWithBytes:bytes length:length];
    return [[NSString alloc] initWithData:trimmed encoding:encoding] ?: @"";
}

static BOOL WriteAll(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = static_cast<const uint8_t *>(bytes);
    while (length != 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return NO;
        cursor += written;
        length -= static_cast<size_t>(written);
    }
    return YES;
}

static BOOL EnsureBackendStateDirectory(NSError **error) {
    const char *path = kBackendStateDirectory.fileSystemRepresentation;
    struct stat info = {};
    if (lstat(path, &info) != 0) {
        if (errno != ENOENT || mkdir(path, 0700) != 0) {
            if (error != nullptr)
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                              code:errno userInfo:nil];
            return NO;
        }
        if (lstat(path, &info) != 0) return NO;
    }
    if (!S_ISDIR(info.st_mode) || info.st_uid != getuid() ||
        (info.st_mode & 077) != 0 || chmod(path, 0700) != 0) {
        if (error != nullptr)
            *error = CardError(4, @"バックエンド用保存先を安全に使用できません。");
        return NO;
    }
    return YES;
}

static BOOL WriteTemporaryRecord(const uint8_t *bytes, size_t length,
                                 NSError **error) {
    if (bytes == nullptr || length == 0 ||
        !EnsureBackendStateDirectory(error)) return NO;
    char temporary[PATH_MAX] = {};
    int count = snprintf(temporary, sizeof(temporary), "%s.tmp.%d",
                         kTemporaryProfilePath.fileSystemRepresentation,
                         getpid());
    if (count <= 0 || static_cast<size_t>(count) >= sizeof(temporary)) {
        if (error != nullptr)
            *error = CardError(4, @"一時ファイル名を作成できませんでした。");
        return NO;
    }
    (void)unlink(temporary);
    int fd = open(temporary,
                  O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                  0600);
    if (fd < 0) {
        if (error != nullptr)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                          code:errno userInfo:nil];
        return NO;
    }
    BOOL success = fchmod(fd, 0600) == 0 &&
                   WriteAll(fd, bytes, length) && fsync(fd) == 0;
    if (close(fd) != 0) success = NO;
    if (success && rename(temporary,
                           kTemporaryProfilePath.fileSystemRepresentation) != 0)
        success = NO;
    int savedError = errno;
    if (!success) (void)unlink(temporary);
    if (!success && error != nullptr)
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                      code:savedError userInfo:nil];
    return success;
}

@interface StudentCard ()
@property(nonatomic, strong) NSMutableData *privateIDm;
@property(nonatomic, strong) NSMutableData *privatePMmTail;
@property(nonatomic, strong) NSMutableArray<NSMutableData *> *privateBlocks;
@end

@implementation StudentCard

- (instancetype)initWithIDm:(NSData *)idm
                    pmmTail:(NSData *)pmmTail
                     blocks:(NSArray<NSData *> *)blocks
                      error:(NSError **)error {
    if (idm.length != 8 || pmmTail.length != 6 ||
        blocks.count != StudentCardBlockCount) {
        if (error != nullptr)
            *error = CardError(1, @"学生証の形式が正しくありません。");
        return nil;
    }
    for (NSData *block in blocks) {
        if (![block isKindOfClass:[NSData class]] || block.length != 16) {
            if (error != nullptr)
                *error = CardError(1, @"学生証のブロック長が正しくありません。");
            return nil;
        }
    }
    self = [super init];
    if (self) {
        _privateIDm = [idm mutableCopy];
        _privatePMmTail = [pmmTail mutableCopy];
        _privateBlocks = [NSMutableArray arrayWithCapacity:blocks.count];
        for (NSData *block in blocks)
            [_privateBlocks addObject:[block mutableCopy]];
    }
    return self;
}

- (void)dealloc {
    SecureZero(_privateIDm.mutableBytes, _privateIDm.length);
    SecureZero(_privatePMmTail.mutableBytes, _privatePMmTail.length);
    for (NSMutableData *block in _privateBlocks)
        SecureZero(block.mutableBytes, block.length);
}

- (NSString *)displayName {
    if (_privateBlocks.count > 1) {
        NSString *name = StringFromBlock(_privateBlocks[1],
                                         NSShiftJISStringEncoding);
        if (name.length != 0) return name;
    }
    return @"学生証";
}

- (NSString *)detailText {
    if (_privateBlocks.count > 0) {
        NSString *info = StringFromBlock(_privateBlocks[0],
                                         NSASCIIStringEncoding);
        if (info.length != 0) return info;
    }
    return @"FeliCa";
}

- (NSString *)idmHex {
    const uint8_t *bytes =
        static_cast<const uint8_t *>(_privateIDm.bytes);
    NSMutableString *hex =
        [NSMutableString stringWithCapacity:_privateIDm.length * 2];
    for (NSUInteger index = 0; index < _privateIDm.length; ++index)
        [hex appendFormat:@"%02X", bytes[index]];
    return hex;
}

- (NSString *)maskedIDm {
    NSString *hex = self.idmHex;
    if (hex.length <= 4) return @"••••";
    return [NSString stringWithFormat:@"••••••••••••%@",
                                      [hex substringFromIndex:hex.length - 4]];
}

- (NSString *)recordFingerprint {
    NSData *record = [self recordData:nil];
    if (record == nil) return @"";
    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {};
    CC_SHA256(record.bytes, (CC_LONG)record.length, digest);
    NSMutableString *hex =
        [NSMutableString stringWithCapacity:sizeof(digest) * 2];
    for (NSUInteger index = 0; index < sizeof(digest); ++index)
        [hex appendFormat:@"%02X", digest[index]];
    SecureZero(digest, sizeof(digest));
    return hex;
}

- (NSData *)recordData:(NSError **)error {
    const uint8_t *idm =
        static_cast<const uint8_t *>(_privateIDm.bytes);
    const uint8_t *pmm =
        static_cast<const uint8_t *>(_privatePMmTail.bytes);
    nfcf::Profile profile = {};
    profile.system_code = StudentCardSystemCode;
    profile.service_code = StudentCardServiceCode;
    memcpy(profile.idm, idm, sizeof(profile.idm));
    memcpy(profile.pmm_tail, pmm, sizeof(profile.pmm_tail));
    profile.block_count = static_cast<uint8_t>(StudentCardBlockCount);
    for (NSUInteger index = 0; index < _privateBlocks.count; ++index)
        memcpy(profile.blocks[index], _privateBlocks[index].bytes,
               nfcf::kBlockSize);

    nfcf::ProfileRecord record = {};
    BOOL valid = nfcf::MakeProfileRecord(profile, &record);
    SecureZero(&profile, sizeof(profile));
    uint8_t encoded[nfcf::kProfileRecordEncodedSize] = {};
    valid = valid && nfcf::EncodeProfileRecord(
        record, encoded, sizeof(encoded));
    SecureZero(&record, sizeof(record));
    if (!valid) {
        SecureZero(encoded, sizeof(encoded));
        if (error != nullptr)
            *error = CardError(3, @"学生証を変換できませんでした。");
        return nil;
    }
    NSData *data = [NSData dataWithBytes:encoded length:sizeof(encoded)];
    SecureZero(encoded, sizeof(encoded));
    return data;
}

- (BOOL)writeTemporaryRecord:(NSError **)error {
    NSData *data = [self recordData:error];
    return data != nil && WriteTemporaryRecord(
        static_cast<const uint8_t *>(data.bytes), data.length, error);
}

+ (instancetype)cardWithRecordData:(NSData *)data error:(NSError **)error {
    nfcf::Profile profile = {};
    if (!DecodeStudentProfile(data, &profile)) {
        SecureZero(&profile, sizeof(profile));
        if (error != nullptr)
            *error = CardError(5, @"保存済み学生証の形式が正しくありません。");
        return nil;
    }
    NSData *idm = [NSData dataWithBytes:profile.idm length:sizeof(profile.idm)];
    NSData *pmm = [NSData dataWithBytes:profile.pmm_tail
                                 length:sizeof(profile.pmm_tail)];
    NSMutableArray<NSData *> *blocks =
        [NSMutableArray arrayWithCapacity:StudentCardBlockCount];
    for (NSUInteger index = 0; index < StudentCardBlockCount; ++index)
        [blocks addObject:[NSData dataWithBytes:profile.blocks[index]
                                        length:nfcf::kBlockSize]];
    StudentCard *card = [[self alloc] initWithIDm:idm pmmTail:pmm
                                           blocks:blocks error:error];
    SecureZero(&profile, sizeof(profile));
    return card;
}

@end
