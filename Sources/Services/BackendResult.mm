#import "BackendResult.h"

static NSString *const kJSONPrefix = @"NFCF_JSON:";

static NSString *StringValue(NSDictionary *dictionary, NSString *key,
                             NSString *fallback) {
    id value = dictionary[key];
    return [value isKindOfClass:[NSString class]] ? value : fallback;
}

@interface BackendResult ()
@property(nonatomic, copy, readwrite) NSString *rawOutput;
@property(nonatomic, assign, readwrite) int exitCode;
@property(nonatomic, assign, readwrite, getter=isSuccess) BOOL success;
@property(nonatomic, copy, readwrite) NSString *command;
@property(nonatomic, copy, readwrite) NSString *state;
@property(nonatomic, copy, readwrite) NSString *routing;
@property(nonatomic, copy, readwrite) NSString *profile;
@property(nonatomic, copy, readwrite) NSString *code;
@property(nonatomic, copy, readwrite) NSString *message;
@property(nonatomic, copy, readwrite) NSString *recordFingerprint;
@end

@implementation BackendResult

- (instancetype)initWithOutput:(NSString *)output exitCode:(int)exitCode {
    self = [super init];
    if (self) {
        _rawOutput = [output copy] ?: @"";
        _exitCode = exitCode;
        _success = exitCode == 0;
        _command = @"unknown";
        _state = @"unknown";
        _routing = @"unknown";
        _profile = @"unknown";
        _code = exitCode == 0 ? @"ok" : @"process-failed";
        _message = @"";
        _recordFingerprint = @"";

        __block NSDictionary *payload = nil;
        NSArray<NSString *> *lines = [_rawOutput componentsSeparatedByCharactersInSet:
            [NSCharacterSet newlineCharacterSet]];
        for (NSString *line in [lines reverseObjectEnumerator]) {
            if (![line hasPrefix:kJSONPrefix]) continue;
            NSString *json = [line substringFromIndex:kJSONPrefix.length];
            NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
            id object = data == nil ? nil
                : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:[NSDictionary class]] &&
                [object[@"schemaVersion"] isEqual:@1]) {
                payload = object;
                break;
            }
        }
        if (payload != nil) {
            _success = [payload[@"success"] isKindOfClass:[NSNumber class]]
                ? [payload[@"success"] boolValue] && exitCode == 0
                : exitCode == 0;
            _command = StringValue(payload, @"command", _command);
            _state = StringValue(payload, @"state", _state);
            _routing = StringValue(payload, @"routing", _routing);
            _profile = StringValue(payload, @"profile", _profile);
            _code = StringValue(payload, @"code", _code);
            _message = StringValue(payload, @"message", _message);
            _recordFingerprint =
                StringValue(payload, @"recordFingerprint", @"").uppercaseString;
        }
    }
    return self;
}

- (BackendResult *)resultByPrependingOutput:(NSString *)output {
    NSString *combined = output.length == 0 ? self.rawOutput
        : [NSString stringWithFormat:@"%@\n%@", output, self.rawOutput];
    return [[BackendResult alloc] initWithOutput:combined
                                        exitCode:self.exitCode];
}

@end
