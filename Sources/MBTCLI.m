#import "MBTCLI.h"

static NSString *const kCLICandidatePaths[] = {
    @"/opt/homebrew/bin/mobilebuildmcp",
    @"/usr/local/bin/mobilebuildmcp",
};

@implementation MBTCLI

+ (NSString *)executablePath {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (size_t i = 0; i < sizeof(kCLICandidatePaths) / sizeof(kCLICandidatePaths[0]); i++) {
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:kCLICandidatePaths[i]]) {
                cached = kCLICandidatePaths[i];
                return;
            }
        }
    });
    return cached;
}

+ (NSString *)pathFlagFor:(NSString *)path {
    return [path hasSuffix:@".xcworkspace"] ? @"--workspace-path" : @"--project-path";
}

+ (NSDictionary *)runJSONCommand:(NSArray<NSString *> *)arguments error:(NSError **)error {
    NSString *executable = [self executablePath];
    if (!executable) {
        if (error) *error = [NSError errorWithDomain:@"MBTCLI" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"mobilebuildmcp not found"}];
        return nil;
    }

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.standardError = [NSPipe pipe];

    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError;
        return nil;
    }
    NSData *data = [out.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];

    if (task.terminationStatus != 0) {
        if (error) *error = [NSError errorWithDomain:@"MBTCLI" code:2
                                           userInfo:@{NSLocalizedDescriptionKey: @"mobilebuildmcp failed"}];
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

+ (NSArray<NSString *> *)fetchSchemesForPath:(NSString *)path error:(NSError **)error {
    NSArray *args = @[@"project-discovery", @"list-schemes", [self pathFlagFor:path], path, @"--output", @"json"];
    NSDictionary *json = [self runJSONCommand:args error:error];
    NSArray *schemes = json[@"data"][@"schemes"];
    return [schemes isKindOfClass:[NSArray class]] ? schemes : @[];
}

+ (NSDictionary<NSString *, NSString *> *)fetchBuildSettingsForPath:(NSString *)path
                                                             scheme:(NSString *)scheme
                                                              error:(NSError **)error {
    NSArray *args = @[@"project-discovery", @"show-build-settings", [self pathFlagFor:path], path,
                      @"--scheme", scheme, @"--output", @"json"];
    NSDictionary *json = [self runJSONCommand:args error:error];
    NSArray *entries = json[@"data"][@"entries"];
    if (![entries isKindOfClass:[NSArray class]]) return @{};

    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (id entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *key = entry[@"key"];
        NSString *value = entry[@"value"];
        if (![key isKindOfClass:[NSString class]] || !key.length) continue;
        if (![value isKindOfClass:[NSString class]]) continue;
        if (!settings[key]) settings[key] = value;
    }
    return settings;
}

+ (NSString *)platformFromBuildSettings:(NSDictionary<NSString *, NSString *> *)settings {
    NSString *name = settings[@"PLATFORM_NAME"];
    if ([name hasPrefix:@"macos"]) return @"macos";
    if ([name hasPrefix:@"iphone"] || [name hasPrefix:@"ios"]) return @"ios";
    return nil;
}

+ (NSArray<NSDictionary *> *)fetchSimulators:(NSError **)error {
    NSDictionary *json = [self runJSONCommand:@[@"simulator", @"list", @"--output", @"json"] error:error];
    NSArray *simulators = json[@"data"][@"simulators"];
    return [simulators isKindOfClass:[NSArray class]] ? simulators : @[];
}

+ (NSArray<NSDictionary *> *)fetchDevices:(NSError **)error {
    NSDictionary *json = [self runJSONCommand:@[@"device", @"list", @"--output", @"json"] error:error];
    NSArray *devices = json[@"data"][@"devices"];
    if (![devices isKindOfClass:[NSArray class]]) return @[];
    return [self physicalDevicesFrom:devices excludingSimulators:[self fetchSimulators:NULL]];
}

+ (NSArray<NSDictionary *> *)physicalDevicesFrom:(NSArray *)devices
                              excludingSimulators:(NSArray *)simulators {
    NSMutableSet<NSString *> *simulatorIDs = [NSMutableSet set];
    for (id simulator in simulators) {
        if (![simulator isKindOfClass:[NSDictionary class]]) continue;
        NSString *simulatorID = simulator[@"simulatorId"];
        if ([simulatorID isKindOfClass:[NSString class]]) [simulatorIDs addObject:simulatorID];
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id device in devices) {
        if (![device isKindOfClass:[NSDictionary class]]) continue;
        NSString *deviceID = device[@"deviceId"];
        if (![deviceID isKindOfClass:[NSString class]] || !deviceID.length) continue;
        if ([simulatorIDs containsObject:deviceID]) continue;
        if (![device[@"isAvailable"] boolValue]) continue;
        [result addObject:device];
    }
    return result;
}

@end
