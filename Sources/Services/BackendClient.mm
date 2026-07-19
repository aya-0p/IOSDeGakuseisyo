#import "BackendClient.h"

#import "BackendResult.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

static NSString *const kBackendControl = @"/var/jb/usr/bin/iosnfcfctl";
static NSString *const kShell = @"/var/jb/usr/bin/sh";
static const NSUInteger kDiagnosticLogLimit = 256 * 1024;
static const NSUInteger kCommandOutputLimit = 1024 * 1024;

@implementation BackendClient

static NSMutableString *DiagnosticLog(void) {
    static NSMutableString *log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ log = [NSMutableString string]; });
    return log;
}

static NSString *RedactedDiagnosticOutput(NSString *output) {
    if (output.length == 0) return output ?: @"";
    NSError *error = nil;
    NSRegularExpression *hexIdentifier = [NSRegularExpression
        regularExpressionWithPattern:@"(?i)(?<![0-9a-f])[0-9a-f]{16,}(?![0-9a-f])"
        options:0 error:&error];
    if (hexIdentifier == nil || error != nil)
        return @"<diagnostic output redacted>";
    return [hexIdentifier stringByReplacingMatchesInString:output
        options:0 range:NSMakeRange(0, output.length)
        withTemplate:@"<hex-redacted>"];
}

static void AppendOutput(NSMutableData *data, const uint8_t *bytes,
                         NSUInteger length, BOOL *overflow) {
    if (*overflow || length == 0) return;
    NSUInteger available = data.length < kCommandOutputLimit
        ? kCommandOutputLimit - data.length : 0;
    NSUInteger accepted = MIN(available, length);
    if (accepted != 0) [data appendBytes:bytes length:accepted];
    if (accepted != length) *overflow = YES;
}

- (BackendResult *)runCommandWithArguments:(NSArray<NSString *> *)arguments {
    int outputPipe[2] = {-1, -1};
    if (pipe(outputPipe) != 0) {
        NSString *message = @"コマンド用のパイプを作成できませんでした。";
        return [[BackendResult alloc] initWithOutput:message exitCode:errno];
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outputPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outputPipe[1]);

    const NSUInteger argumentCount = arguments.count + 3;
    char **argv = static_cast<char **>(
        calloc(argumentCount, sizeof(char *)));
    argv[0] = strdup(kShell.fileSystemRepresentation);
    argv[1] = strdup(kBackendControl.fileSystemRepresentation);
    for (NSUInteger index = 0; index < arguments.count; ++index)
        argv[index + 2] = strdup(arguments[index].fileSystemRepresentation);
    argv[argumentCount - 1] = NULL;

    pid_t process = 0;
    int spawnResult = posix_spawn(&process, argv[0], &actions, NULL, argv,
                                  environ);
    posix_spawn_file_actions_destroy(&actions);
    close(outputPipe[1]);
    for (NSUInteger index = 0; index + 1 < argumentCount; ++index)
        free(argv[index]);
    free(argv);
    if (spawnResult != 0) {
        close(outputPipe[0]);
        NSString *message = [NSString stringWithFormat:
            @"バックエンドを起動できませんでした（%d）。", spawnResult];
        return [[BackendResult alloc] initWithOutput:message
                                            exitCode:spawnResult];
    }

    int flags = fcntl(outputPipe[0], F_GETFL, 0);
    if (flags >= 0) (void)fcntl(outputPipe[0], F_SETFL, flags | O_NONBLOCK);
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    BOOL overflow = NO;
    int status = 0;
    time_t started = time(NULL);
    for (;;) {
        ssize_t count = 0;
        while ((count = read(outputPipe[0], buffer, sizeof(buffer))) > 0)
            AppendOutput(data, buffer, (NSUInteger)count, &overflow);
        if (overflow) {
            (void)kill(process, SIGKILL);
            (void)waitpid(process, &status, 0);
            [data appendData:[@"\nバックエンド出力が1 MBを超えたため停止しました。"
                dataUsingEncoding:NSUTF8StringEncoding]];
            status = 125 << 8;
            break;
        }
        if (waitpid(process, &status, WNOHANG) == process) break;
        if (time(NULL) - started >= 45) {
            (void)kill(process, SIGTERM);
            usleep(200000);
            if (waitpid(process, &status, WNOHANG) == 0)
                (void)kill(process, SIGKILL);
            (void)waitpid(process, &status, 0);
            [data appendData:[@"\nバックエンド処理がタイムアウトしました。"
                dataUsingEncoding:NSUTF8StringEncoding]];
            status = 124 << 8;
            break;
        }
        usleep(50000);
    }
    ssize_t remaining = 0;
    while (!overflow &&
           (remaining = read(outputPipe[0], buffer, sizeof(buffer))) > 0)
        AppendOutput(data, buffer, (NSUInteger)remaining, &overflow);
    close(outputPipe[0]);
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128;
    NSString *output = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    NSString *raw = output.length > 0 ? output : @"出力はありません。";
    BackendResult *result = [[BackendResult alloc] initWithOutput:raw
                                                         exitCode:code];
    @synchronized (DiagnosticLog()) {
        [DiagnosticLog() appendFormat:@"\n[%@] $ iosnfcfctl %@\nexit=%d\n%@\n",
            [NSDate date], [arguments componentsJoinedByString:@" "], code,
            RedactedDiagnosticOutput(raw)];
        if (DiagnosticLog().length > kDiagnosticLogLimit) {
            NSUInteger excess = DiagnosticLog().length - kDiagnosticLogLimit;
            NSRange newline = [DiagnosticLog() rangeOfString:@"\n"
                options:0 range:NSMakeRange(excess,
                    DiagnosticLog().length - excess)];
            NSUInteger trim = newline.location == NSNotFound
                ? excess : NSMaxRange(newline);
            [DiagnosticLog() deleteCharactersInRange:NSMakeRange(0, trim)];
        }
    }
    return result;
}

- (NSString *)diagnosticLog {
    @synchronized (DiagnosticLog()) {
        return RedactedDiagnosticOutput([DiagnosticLog() copy]);
    }
}

@end
