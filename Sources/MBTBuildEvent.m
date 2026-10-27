#import "MBTBuildEvent.h"

static BOOL MBTIsDigits(NSString *s) {
    if (s.length == 0) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

// "path/to/File.swift:11" or "path/to/File.swift:11:30"
static void MBTSplitLocation(NSString *location, NSString **outPath, NSInteger *outLine) {
    if (![location isKindOfClass:[NSString class]] || location.length == 0) return;
    NSArray<NSString *> *parts = [location componentsSeparatedByString:@":"];
    NSUInteger n = parts.count;
    if (n < 2 || !MBTIsDigits(parts[n - 1])) return;
    if (n >= 3 && MBTIsDigits(parts[n - 2])) {
        *outLine = parts[n - 2].integerValue;
        *outPath = [[parts subarrayWithRange:NSMakeRange(0, n - 2)] componentsJoinedByString:@":"];
    } else {
        *outLine = parts[n - 1].integerValue;
        *outPath = [[parts subarrayWithRange:NSMakeRange(0, n - 1)] componentsJoinedByString:@":"];
    }
}

@implementation MBTBuildEvent

- (BOOL)isDisplayable {
    if (self.kind != MBTEventKindDiagnostic) return NO;
    if (![self.severity isEqualToString:@"error"]) return NO;
    NSString *firstLine = [self.message componentsSeparatedByString:@"\n"].firstObject ?: @"";
    return self.filePath.length > 0 || ![firstLine hasPrefix:@"|"];
}

+ (instancetype)eventFromJSONLine:(NSData *)line {
    if (line.length == 0) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) return nil;

    NSString *name = object[@"event"];
    if (![name isKindOfClass:[NSString class]]) return nil;

    MBTBuildEvent *event = [MBTBuildEvent new];
    if ([name hasSuffix:@".build-stage"]) {
        event->_kind = MBTEventKindStage;
        event.stage = object[@"stage"];
        return event;
    }
    if ([name hasSuffix:@".compiler-diagnostic"]) {
        event->_kind = MBTEventKindDiagnostic;
        event.severity = object[@"severity"];
        event.message = object[@"message"];
        NSString *path = nil;
        NSInteger lineNumber = 0;
        MBTSplitLocation(object[@"location"], &path, &lineNumber);
        event.filePath = path;
        event.lineNumber = lineNumber;
        return event;
    }
    if ([name hasSuffix:@".phase"]) {
        event->_kind = MBTEventKindPhase;
        event.phase = object[@"phase"];
        event.phaseStarted = [object[@"status"] isEqual:@"started"];
        return event;
    }
    if ([name hasSuffix:@".build-summary"]) {
        event->_kind = MBTEventKindSummary;
        event.status = object[@"status"];
        event.durationMs = [object[@"durationMs"] integerValue];
        return event;
    }
    event->_kind = MBTEventKindUnknown;
    return event;
}

@end
