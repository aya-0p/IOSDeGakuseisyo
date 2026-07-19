#import "StudentCardRepository.h"

#import "StudentCard.h"

#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>

#include <sys/stat.h>
#include <unistd.h>

static NSString *const kRepositoryErrorDomain =
    @"org.hoshitsugi.iosdegakuseisyo.repository";
static NSString *const kCardsDirectory =
    @"/var/mobile/Library/Preferences/org.hoshitsugi.iosdegakuseisyo.cards";
static NSString *const kIndexPath =
    @"/var/mobile/Library/Preferences/org.hoshitsugi.iosdegakuseisyo.cards.index.json";
static NSString *const kKeychainService =
    @"org.hoshitsugi.iosdegakuseisyo.storage";
static NSString *const kKeychainAccessGroup =
    @"org.hoshitsugi.iosdegakuseisyo";
static const uint8_t kEncryptedMagic[8] = {
    'F', 'S', 'C', 'A', 'R', 'D', '0', '2',
};
static const NSUInteger kStorageKeyLength = 64;

static void SecureZero(void *bytes, size_t length) {
    volatile uint8_t *cursor = static_cast<volatile uint8_t *>(bytes);
    while (cursor != nullptr && length-- != 0) *cursor++ = 0;
}

static NSError *RepositoryError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:kRepositoryErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSDictionary *KeychainQuery(NSString *service, NSString *group) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: service,
             (__bridge id)kSecAttrAccount: @"records",
             (__bridge id)kSecAttrAccessGroup: group};
}

static NSData *ReadKey(NSDictionary *base, OSStatus *status) {
    NSMutableDictionary *query = [base mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = nullptr;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    return *status == errSecSuccess ? CFBridgingRelease(result) : nil;
}

static OSStatus AddKey(NSData *key, NSDictionary *base) {
    NSMutableDictionary *add = [base mutableCopy];
    add[(__bridge id)kSecValueData] = key;
    add[(__bridge id)kSecAttrAccessible] =
        (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)add, nullptr);
}

static NSData *ExistingKeyAfterDuplicate(NSDictionary *query) {
    OSStatus status = errSecSuccess;
    NSData *key = ReadKey(query, &status);
    return status == errSecSuccess && key.length == kStorageKeyLength
        ? key : nil;
}

static NSData *StorageKey(NSError **error) {
    NSDictionary *current = KeychainQuery(kKeychainService,
                                           kKeychainAccessGroup);
    OSStatus status = errSecSuccess;
    NSData *key = ReadKey(current, &status);
    if (status == errSecSuccess) {
        if (key.length == kStorageKeyLength) return key;
        if (error != nullptr)
            *error = RepositoryError(10, @"Keychainの保存鍵が壊れています。");
        return nil;
    }
    if (status != errSecItemNotFound && status != errSecSuccess) {
        if (error != nullptr)
            *error = RepositoryError(10, @"保存鍵をKeychainから読み込めませんでした。");
        return nil;
    }

    NSMutableData *generated = [NSMutableData dataWithLength:kStorageKeyLength];
    if (SecRandomCopyBytes(kSecRandomDefault, generated.length,
                           generated.mutableBytes) != errSecSuccess) {
        SecureZero(generated.mutableBytes, generated.length);
        if (error != nullptr)
            *error = RepositoryError(10, @"安全な保存鍵を作成できませんでした。");
        return nil;
    }
    OSStatus addStatus = AddKey(generated, current);
    if (addStatus == errSecSuccess) return generated;
    if (addStatus == errSecDuplicateItem) {
        NSData *racedKey = ExistingKeyAfterDuplicate(current);
        SecureZero(generated.mutableBytes, generated.length);
        if (racedKey != nil) return racedKey;
    } else {
        SecureZero(generated.mutableBytes, generated.length);
    }
    if (error != nullptr)
        *error = RepositoryError(10, @"安全な保存鍵を保存できませんでした。");
    return nil;
}

static NSData *EncryptRecord(NSData *plain, NSError **error) {
    NSData *key = StorageKey(error);
    if (key == nil) return nil;
    uint8_t iv[kCCBlockSizeAES128] = {};
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(iv), iv) != errSecSuccess) {
        if (error != nullptr)
            *error = RepositoryError(11, @"暗号化用乱数を生成できませんでした。");
        return nil;
    }
    NSMutableData *cipher =
        [NSMutableData dataWithLength:plain.length + kCCBlockSizeAES128];
    size_t written = 0;
    CCCryptorStatus cryptStatus = CCCrypt(
        kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        key.bytes, kCCKeySizeAES256, iv, plain.bytes, plain.length,
        cipher.mutableBytes, cipher.length, &written);
    if (cryptStatus != kCCSuccess) {
        if (error != nullptr)
            *error = RepositoryError(11, @"学生証を暗号化できませんでした。");
        return nil;
    }
    cipher.length = written;
    NSMutableData *envelope = [NSMutableData dataWithBytes:kEncryptedMagic
                                                    length:sizeof(kEncryptedMagic)];
    [envelope appendBytes:iv length:sizeof(iv)];
    [envelope appendData:cipher];
    uint8_t authentication[CC_SHA256_DIGEST_LENGTH] = {};
    const uint8_t *keyBytes = static_cast<const uint8_t *>(key.bytes);
    CCHmac(kCCHmacAlgSHA256, keyBytes + kCCKeySizeAES256, kCCKeySizeAES256,
           envelope.bytes, envelope.length, authentication);
    [envelope appendBytes:authentication length:sizeof(authentication)];
    SecureZero(authentication, sizeof(authentication));
    SecureZero(cipher.mutableBytes, cipher.length);
    return envelope;
}

static NSData *DecryptRecord(NSData *stored, NSError **error) {
    if (stored.length < sizeof(kEncryptedMagic) ||
        memcmp(stored.bytes, kEncryptedMagic, sizeof(kEncryptedMagic)) != 0) {
        if (error != nullptr)
            *error = RepositoryError(12, @"保存済み学生証の形式が正しくありません。");
        return nil;
    }
    const NSUInteger headerLength = sizeof(kEncryptedMagic) + kCCBlockSizeAES128;
    if (stored.length <= headerLength + CC_SHA256_DIGEST_LENGTH) {
        if (error != nullptr)
            *error = RepositoryError(12, @"暗号化された学生証が壊れています。");
        return nil;
    }
    NSData *key = StorageKey(error);
    if (key == nil) return nil;
    NSUInteger authenticatedLength = stored.length - CC_SHA256_DIGEST_LENGTH;
    uint8_t expected[CC_SHA256_DIGEST_LENGTH] = {};
    const uint8_t *keyBytes = static_cast<const uint8_t *>(key.bytes);
    CCHmac(kCCHmacAlgSHA256, keyBytes + kCCKeySizeAES256, kCCKeySizeAES256,
           stored.bytes, authenticatedLength, expected);
    const uint8_t *bytes = static_cast<const uint8_t *>(stored.bytes);
    uint8_t difference = 0;
    for (NSUInteger index = 0; index < sizeof(expected); ++index)
        difference |= expected[index] ^ bytes[authenticatedLength + index];
    SecureZero(expected, sizeof(expected));
    if (difference != 0) {
        if (error != nullptr)
            *error = RepositoryError(12, @"学生証データの認証に失敗しました。");
        return nil;
    }
    const void *iv = bytes + sizeof(kEncryptedMagic);
    const void *cipherBytes = bytes + headerLength;
    NSUInteger cipherLength = authenticatedLength - headerLength;
    NSMutableData *plain = [NSMutableData dataWithLength:cipherLength];
    size_t written = 0;
    CCCryptorStatus cryptStatus = CCCrypt(
        kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        key.bytes, kCCKeySizeAES256, iv, cipherBytes, cipherLength,
        plain.mutableBytes, plain.length, &written);
    if (cryptStatus != kCCSuccess) {
        if (error != nullptr)
            *error = RepositoryError(12, @"学生証を復号できませんでした。");
        return nil;
    }
    plain.length = written;
    return plain;
}

static BOOL WriteProtectedData(NSData *data, NSString *path, NSError **error) {
    BOOL success = [data writeToFile:path
        options:NSDataWritingAtomic |
                NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication
        error:error];
    if (success) (void)chmod(path.fileSystemRepresentation, 0600);
    return success;
}

static BOOL EnsureCardsDirectory(NSError **error) {
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:kCardsDirectory
            withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions: @(0700)}
                                  error:error]) return NO;
    (void)[manager setAttributes:@{
        NSFileProtectionKey:
            NSFileProtectionCompleteUntilFirstUserAuthentication,
        NSFilePosixPermissions: @(0700),
    } ofItemAtPath:kCardsDirectory error:nil];
    return YES;
}

static BOOL SaveCard(StudentCard *card, NSString *path, NSError **error) {
    NSData *plain = [card recordData:error];
    if (plain == nil) return NO;
    NSData *encrypted = EncryptRecord(plain, error);
    return encrypted != nil && WriteProtectedData(encrypted, path, error);
}

static StudentCard *LoadCard(NSString *path, NSError **error) {
    NSData *stored = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (stored == nil) return nil;
    NSData *plain = DecryptRecord(stored, error);
    return plain == nil ? nil
        : [StudentCard cardWithRecordData:plain error:error];
}

static NSDictionary *ReadIndex(void) {
    NSData *json = [NSData dataWithContentsOfFile:kIndexPath];
    id object = json == nil ? nil
        : [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

@implementation StudentCardRepository

+ (NSMutableArray<StudentCard *> *)loadAllCards {
    if (!EnsureCardsDirectory(nil)) return nil;
    NSDictionary *root = ReadIndex();
    NSArray *entries = root[@"cards"];
    NSString *generation = root[@"generation"];
    if (![root[@"version"] isEqual:@3] ||
        ![entries isKindOfClass:[NSArray class]] || entries.count == 0 ||
        ![generation isKindOfClass:[NSString class]]) return nil;
    NSRegularExpression *generationPattern = [NSRegularExpression
        regularExpressionWithPattern:@"^generation\\.[0-9A-Fa-f-]{36}$"
        options:0 error:nil];
    if ([generationPattern firstMatchInString:generation options:0
            range:NSMakeRange(0, generation.length)] == nil) return nil;
    NSString *base = [kCardsDirectory stringByAppendingPathComponent:generation];
    NSRegularExpression *filePattern = [NSRegularExpression
        regularExpressionWithPattern:@"^card\\.[0-9]+\\.record$"
        options:0 error:nil];
    NSMutableArray<StudentCard *> *cards = [NSMutableArray array];
    for (id entry in entries) {
        NSString *name = [entry isKindOfClass:[NSDictionary class]]
            ? entry[@"file"] : nil;
        if (![name isKindOfClass:[NSString class]] ||
            [filePattern firstMatchInString:name options:0
                range:NSMakeRange(0, name.length)] == nil) return nil;
        StudentCard *card = LoadCard(
            [base stringByAppendingPathComponent:name], nil);
        if (card == nil) return nil;
        [cards addObject:card];
    }
    return cards.count == 0 ? nil : cards;
}

+ (NSInteger)savedSelectedIndex {
    NSDictionary *root = ReadIndex();
    if (![root[@"version"] isEqual:@3]) return NSNotFound;
    NSNumber *selected = root[@"selectedIndex"];
    return [selected isKindOfClass:[NSNumber class]]
        ? selected.integerValue : NSNotFound;
}

+ (BOOL)saveCards:(NSArray<StudentCard *> *)cards
     selectedIndex:(NSInteger)selectedIndex
             error:(NSError **)error {
    if (!EnsureCardsDirectory(error)) return NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *generation = cards.count == 0 ? @""
        : [@"generation." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *generationPath = generation.length == 0 ? nil
        : [kCardsDirectory stringByAppendingPathComponent:generation];
    if (generationPath != nil && ![manager createDirectoryAtPath:generationPath
            withIntermediateDirectories:NO
                             attributes:@{NSFilePosixPermissions: @(0700)}
                                  error:error]) return NO;

    NSMutableArray *entries = [NSMutableArray arrayWithCapacity:cards.count];
    for (NSUInteger index = 0; index < cards.count; ++index) {
        NSString *name = [NSString stringWithFormat:@"card.%lu.record",
                                                   (unsigned long)index];
        if (!SaveCard(cards[index],
                      [generationPath stringByAppendingPathComponent:name],
                      error)) {
            [manager removeItemAtPath:generationPath error:nil];
            return NO;
        }
        [entries addObject:@{@"file": name}];
    }
    NSDictionary *root = @{
        @"version": @3,
        @"generation": generation,
        @"selectedIndex": @(selectedIndex),
        @"cards": entries,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:root
                                                   options:0 error:error];
    if (json == nil || !WriteProtectedData(json, kIndexPath, error)) {
        if (generationPath != nil)
            [manager removeItemAtPath:generationPath error:nil];
        return NO;
    }

    // The index now points to the complete new generation. Old generations
    // can be removed without risking a mixed or partially written card set.
    for (NSString *name in
         [manager contentsOfDirectoryAtPath:kCardsDirectory error:nil] ?: @[]) {
        BOOL oldGeneration = [name hasPrefix:@"generation."] &&
                             ![name isEqual:generation];
        if (oldGeneration)
            [manager removeItemAtPath:
                [kCardsDirectory stringByAppendingPathComponent:name]
                               error:nil];
    }
    return YES;
}

+ (BOOL)deleteStorageKeys:(NSError **)error {
    OSStatus current = SecItemDelete((__bridge CFDictionaryRef)
        KeychainQuery(kKeychainService, kKeychainAccessGroup));
    BOOL currentOK = current == errSecSuccess || current == errSecItemNotFound;
    if (currentOK) return YES;
    if (error != nullptr)
        *error = RepositoryError(10, @"Keychainの保存鍵を削除できませんでした。");
    return NO;
}

@end
