#import "MBTBuildRunner.h"
#import "MBTCLI.h"
#import "MBTLineBuffer.h"

@interface MBTBuildRunner ()
@property (nonatomic, strong) NSTask *task;
@property (nonatomic, strong) id terminationObserver;
@property (nonatomic, strong) MBTLineBuffer *lineBuffer;
@end

@implementation MBTBuildRunner

- (instancetype)init {
    self = [super init];
    if (self) {
        _lineBuffer = [MBTLineBuffer new];
    }
    return self;
}

- (BOOL)isRunning {
    return self.task != nil;
}

- (void)runProject:(MBTProject *)project target:(MBTTarget *)target {
    if (self.task) return;

    NSString *executable = [MBTCLI executablePath];
    if (!executable) {
        if (self.onFinish) self.onFinish(NO);
        return;
    }

    NSString *pathFlag = [project.path hasSuffix:@".xcworkspace"] ? @"--workspace-path" : @"--project-path";
    BOOL isMac = target.isMacOS;
    NSString *workflow = isMac ? @"macos" : @"simulator";
    NSMutableArray<NSString *> *args = [@[workflow, @"build-and-run", pathFlag, project.path] mutableCopy];
    if (target.scheme.length) [args addObjectsFromArray:@[@"--scheme", target.scheme]];
    if (!isMac && target.simulatorID.length) [args addObjectsFromArray:@[@"--simulator-id", target.simulatorID]];
    if (project.configuration.length) [args addObjectsFromArray:@[@"--configuration", project.configuration]];
    [args addObjectsFromArray:@[@"--output", @"jsonl"]];

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = args;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    __weak typeof(self) weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) return;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        for (NSData *line in [self.lineBuffer appendData:data]) {
            MBTBuildEvent *event = [MBTBuildEvent eventFromJSONLine:line];
            if (!event) continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.onEvent) self.onEvent(event);
            });
        }
    };

    self.task = task;
    self.terminationObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSTaskDidTerminateNotification
                    object:task
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        pipe.fileHandleForReading.readabilityHandler = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self.terminationObserver];
        self.terminationObserver = nil;
        self.task = nil;
        BOOL success = task.terminationStatus == 0;
        if (self.onFinish) self.onFinish(success);
    }];

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.terminationObserver];
        self.terminationObserver = nil;
        self.task = nil;
        if (self.onFinish) self.onFinish(NO);
    }
}

- (void)cancel {
    [self.task terminate];
}

@end
