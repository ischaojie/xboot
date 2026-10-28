#import <Foundation/Foundation.h>
#import "MBTBuildEvent.h"
#import "MBTCLI.h"
#import "MBTLineBuffer.h"
#import "MBTProject.h"
#import "MBTProjectStore.h"
#import "MBTTarget.h"

static int gFailures = 0;
static int gChecks = 0;

#define EXPECT(cond)                                                          \
    do {                                                                      \
        gChecks++;                                                            \
        if (!(cond)) {                                                        \
            gFailures++;                                                      \
            fprintf(stderr, "  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); \
        }                                                                     \
    } while (0)

static NSData *Line(NSString *json) {
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

static void test_parses_build_stage(void) {
    MBTBuildEvent *e = [MBTBuildEvent
        eventFromJSONLine:Line(@"{\"event\":\"build-result.build-stage\",\"stage\":\"COMPILING\",\"message\":\"Compiling\"}")];
    EXPECT(e != nil);
    EXPECT(e.kind == MBTEventKindStage);
    EXPECT([e.stage isEqualToString:@"COMPILING"]);
}

static void test_parses_compiler_diagnostic(void) {
    NSString *json = @"{\"event\":\"build-result.compiler-diagnostic\","
                     @"\"severity\":\"error\","
                     @"\"message\":\"cannot convert value of type 'String' to specified type 'Int'\","
                     @"\"location\":\"/tmp/probe/ContentView.swift:11\"}";
    MBTBuildEvent *e = [MBTBuildEvent eventFromJSONLine:Line(json)];
    EXPECT(e != nil);
    EXPECT(e.kind == MBTEventKindDiagnostic);
    EXPECT([e.severity isEqualToString:@"error"]);
    EXPECT([e.message hasPrefix:@"cannot convert"]);
    EXPECT([e.filePath isEqualToString:@"/tmp/probe/ContentView.swift"]);
    EXPECT(e.lineNumber == 11);
}

static void test_parses_phase_and_summary(void) {
    MBTBuildEvent *phase = [MBTBuildEvent
        eventFromJSONLine:Line(@"{\"event\":\"build-run-result.phase\",\"phase\":\"install-app\",\"status\":\"started\"}")];
    EXPECT(phase.kind == MBTEventKindPhase);
    EXPECT([phase.phase isEqualToString:@"install-app"]);
    EXPECT(phase.phaseStarted);

    MBTBuildEvent *done = [MBTBuildEvent
        eventFromJSONLine:Line(@"{\"event\":\"build-run-result.phase\",\"phase\":\"install-app\",\"status\":\"succeeded\"}")];
    EXPECT(!done.phaseStarted);

    MBTBuildEvent *summary = [MBTBuildEvent
        eventFromJSONLine:Line(@"{\"event\":\"build-result.build-summary\",\"status\":\"FAILED\",\"durationMs\":3926}")];
    EXPECT(summary.kind == MBTEventKindSummary);
    EXPECT([summary.status isEqualToString:@"FAILED"]);
    EXPECT(summary.durationMs == 3926);
}

static void test_ignores_garbage(void) {
    EXPECT([MBTBuildEvent eventFromJSONLine:Line(@"not json")] == nil);
    EXPECT([MBTBuildEvent eventFromJSONLine:Line(@"[1,2]")] == nil);
    EXPECT([MBTBuildEvent eventFromJSONLine:Line(@"")] == nil);
    MBTBuildEvent *other = [MBTBuildEvent eventFromJSONLine:Line(@"{\"event\":\"build-result.invocation\"}")];
    EXPECT(other != nil);
    EXPECT(other.kind == MBTEventKindUnknown);
}

static NSUserDefaults *TestDefaults(void) {
    NSString *suite = [NSString stringWithFormat:@"xboot.tests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:suite];
    return d;
}

static void test_project_targets(void) {
    MBTProject *project = [MBTProject projectWithPath:@"/tmp/A.xcodeproj"];
    EXPECT(project.targets.count == 0);

    MBTTarget *target = [project addTargetWithScheme:@"App"];
    EXPECT(project.targets.count == 1);
    EXPECT([target.scheme isEqualToString:@"App"]);
    EXPECT([project targetForScheme:@"App"] == target);

    [project addTargetWithScheme:@"App"];
    EXPECT(project.targets.count == 1);

    MBTTarget *second = [project addTargetWithScheme:@"Widget"];
    second.platform = @"macos";
    EXPECT([second isMacOS]);
    EXPECT(![target isMacOS]);
    EXPECT(project.targets.count == 2);

    [project removeTargetWithScheme:@"App"];
    EXPECT(project.targets.count == 1);
    EXPECT([project targetForScheme:@"App"] == nil);
}

static void test_store_add_and_order(void) {
    NSUserDefaults *defaults = TestDefaults();
    MBTProjectStore *store = [[MBTProjectStore alloc] initWithDefaults:defaults];
    [store addProjectAtPath:@"/tmp/A.xcodeproj"];
    [store addProjectAtPath:@"/tmp/B.xcworkspace"];
    EXPECT(store.projects.count == 2);
    EXPECT([store.projects[0].path isEqualToString:@"/tmp/B.xcworkspace"]);
    EXPECT([[store.projects[0] displayName] isEqualToString:@"B"]);

    [store touchProjectAtPath:@"/tmp/A.xcodeproj"];
    EXPECT([store.projects[0].path isEqualToString:@"/tmp/A.xcodeproj"]);

    MBTProject *a = [store projectAtPath:@"/tmp/A.xcodeproj"];
    MBTTarget *target = [a addTargetWithScheme:@"Alpha"];
    target.platform = @"ios";
    target.simulatorID = @"UDID-1";
    target.simulatorName = @"iPhone 17";
    [store save];

    MBTProjectStore *reloaded = [[MBTProjectStore alloc] initWithDefaults:defaults];
    EXPECT(reloaded.projects.count == 2);
    MBTProject *reloadedA = [reloaded projectAtPath:@"/tmp/A.xcodeproj"];
    EXPECT(reloadedA.targets.count == 1);
    EXPECT([[[reloadedA targetForScheme:@"Alpha"] simulatorName] isEqualToString:@"iPhone 17"]);
    EXPECT([[[reloadedA targetForScheme:@"Alpha"] platform] isEqualToString:@"ios"]);
    EXPECT([reloaded.projects[0].path isEqualToString:@"/tmp/A.xcodeproj"]);

    [reloaded removeProjectAtPath:@"/tmp/A.xcodeproj"];
    EXPECT(reloaded.projects.count == 1);
}

static void test_recent_simulators(void) {
    NSUserDefaults *defaults = TestDefaults();
    MBTProjectStore *store = [[MBTProjectStore alloc] initWithDefaults:defaults];
    EXPECT(store.recentSimulatorIDs.count == 0);

    [store recordSimulatorUse:@"A"];
    [store recordSimulatorUse:@"B"];
    EXPECT(store.recentSimulatorIDs.count == 2);
    EXPECT([store.recentSimulatorIDs.firstObject isEqualToString:@"B"]);

    // Using an old device again moves it to the front instead of duplicating it.
    [store recordSimulatorUse:@"A"];
    EXPECT([store.recentSimulatorIDs.firstObject isEqualToString:@"A"]);
    EXPECT(store.recentSimulatorIDs.count == 2);

    [store recordSimulatorUse:@"C"];
    [store recordSimulatorUse:@"D"];
    EXPECT(store.recentSimulatorIDs.count == 3);
    EXPECT([store.recentSimulatorIDs.firstObject isEqualToString:@"D"]);
    EXPECT(![store.recentSimulatorIDs containsObject:@"B"]);

    MBTProjectStore *reloaded = [[MBTProjectStore alloc] initWithDefaults:defaults];
    EXPECT([reloaded.recentSimulatorIDs.firstObject isEqualToString:@"D"]);
    EXPECT(reloaded.recentSimulatorIDs.count == 3);

    [reloaded recordSimulatorUse:nil];
    EXPECT(reloaded.recentSimulatorIDs.count == 3);
}

static void test_store_migrates_legacy_single_scheme(void) {
    NSUserDefaults *defaults = TestDefaults();
    NSArray *legacy = @[@{
        @"path": @"/tmp/Old.xcodeproj",
        @"scheme": @"App",
        @"simulatorID": @"UDID-9",
        @"simulatorName": @"iPhone 17",
        @"platform": @"ios",
        @"configuration": @"Debug",
        @"lastUsed": @0,
    }];
    [defaults setObject:legacy forKey:@"projects"];

    MBTProjectStore *store = [[MBTProjectStore alloc] initWithDefaults:defaults];
    MBTProject *project = store.projects.firstObject;
    EXPECT(project.targets.count == 1);
    MBTTarget *target = project.targets.firstObject;
    EXPECT([target.scheme isEqualToString:@"App"]);
    EXPECT([target.simulatorID isEqualToString:@"UDID-9"]);
    EXPECT([target.platform isEqualToString:@"ios"]);
}

static NSString *String(NSData *data) {
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static void test_line_buffer_splits_across_chunks(void) {
    MBTLineBuffer *buffer = [MBTLineBuffer new];

    NSArray<NSData *> *lines = [buffer appendData:[@"a\nb\n" dataUsingEncoding:NSUTF8StringEncoding]];
    EXPECT(lines.count == 2);
    EXPECT([String(lines[0]) isEqualToString:@"a"]);
    EXPECT([String(lines[1]) isEqualToString:@"b"]);

    lines = [buffer appendData:[@"he" dataUsingEncoding:NSUTF8StringEncoding]];
    EXPECT(lines.count == 0);
    lines = [buffer appendData:[@"llo\n" dataUsingEncoding:NSUTF8StringEncoding]];
    EXPECT(lines.count == 1);
    EXPECT([String(lines[0]) isEqualToString:@"hello"]);

    lines = [buffer appendData:[@"tail" dataUsingEncoding:NSUTF8StringEncoding]];
    EXPECT(lines.count == 0);
    lines = [buffer appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    EXPECT(lines.count == 1);
    EXPECT([String(lines[0]) isEqualToString:@"tail"]);
}

static void test_platform_detection(void) {
    EXPECT([[MBTCLI platformFromBuildSettings:@{ @"PLATFORM_NAME": @"macosx" }] isEqualToString:@"macos"]);
    EXPECT([[MBTCLI platformFromBuildSettings:@{ @"PLATFORM_NAME": @"iphoneos" }] isEqualToString:@"ios"]);
    EXPECT([[MBTCLI platformFromBuildSettings:@{ @"PLATFORM_NAME": @"iphonesimulator" }] isEqualToString:@"ios"]);
    EXPECT([MBTCLI platformFromBuildSettings:@{}] == nil);
    EXPECT([MBTCLI platformFromBuildSettings:@{ @"PLATFORM_NAME": @"" }] == nil);
    // An aggregate scheme reports no platform at all.
    EXPECT([MBTCLI platformFromBuildSettings:@{ @"PRODUCT_TYPE": @"com.apple.product-type.framework" }] == nil);
}

static MBTBuildEvent *Diagnostic(NSString *json) {
    return [MBTBuildEvent eventFromJSONLine:Line(json)];
}

static void test_diagnostic_display_filter(void) {
    MBTBuildEvent *withLocation = Diagnostic(@"{\"event\":\"build-result.compiler-diagnostic\","
                                             @"\"severity\":\"error\",\"message\":\"bad\","
                                             @"\"location\":\"/tmp/A.swift:3\"}");
    EXPECT(withLocation.isDisplayable);

    // xcodebuild emits continuation lines without a location; they duplicate the
    // error above them and must not reach the list.
    MBTBuildEvent *continuation = Diagnostic(@"{\"event\":\"build-result.compiler-diagnostic\","
                                             @"\"severity\":\"error\",\"message\":\"| `- error: bad\"}");
    EXPECT(!continuation.isDisplayable);

    // A real error can still lack a location (linker, signing).
    MBTBuildEvent *noLocation = Diagnostic(@"{\"event\":\"build-result.compiler-diagnostic\","
                                           @"\"severity\":\"error\",\"message\":\"linker failed\"}");
    EXPECT(noLocation.isDisplayable);

    MBTBuildEvent *warning = Diagnostic(@"{\"event\":\"build-result.compiler-diagnostic\","
                                        @"\"severity\":\"warning\",\"message\":\"meh\","
                                        @"\"location\":\"/tmp/A.swift:1\"}");
    EXPECT(!warning.isDisplayable);

    EXPECT(![MBTBuildEvent eventFromJSONLine:Line(@"{\"event\":\"build-result.build-summary\",\"status\":\"FAILED\"}")].isDisplayable);
}

static void test_location_with_column(void) {
    MBTBuildEvent *event = Diagnostic(@"{\"event\":\"build-result.compiler-diagnostic\","
                                      @"\"severity\":\"error\",\"message\":\"m\","
                                      @"\"location\":\"/tmp/A.swift:11:30\"}");
    EXPECT([event.filePath isEqualToString:@"/tmp/A.swift"]);
    EXPECT(event.lineNumber == 11);
}

static void test_target_round_trip(void) {
    MBTTarget *target = [MBTTarget targetWithScheme:@"App"];
    target.platform = @"macos";
    target.probed = YES;
    target.kindLabel = nil;

    MBTTarget *copy = [MBTTarget targetWithDictionary:[target dictionaryRepresentation]];
    EXPECT([copy.scheme isEqualToString:@"App"]);
    EXPECT([copy.platform isEqualToString:@"macos"]);
    EXPECT(copy.probed);
    EXPECT([copy isMacOS]);

    MBTTarget *skipped = [MBTTarget targetWithScheme:@"Widget"];
    skipped.probed = YES;
    skipped.kindLabel = @"extension";
    MBTTarget *skippedCopy = [MBTTarget targetWithDictionary:[skipped dictionaryRepresentation]];
    EXPECT(!skippedCopy.isMacOS);
    EXPECT([skippedCopy.kindLabel isEqualToString:@"extension"]);
}

static void test_device_target_round_trip(void) {
    MBTTarget *target = [MBTTarget targetWithScheme:@"App"];
    target.platform = @"ios";
    target.simulatorID = @"BB167D31-E074-5354-B71B-4C69C87B8CDB";
    target.onDevice = YES;
    MBTTarget *copy = [MBTTarget targetWithDictionary:[target dictionaryRepresentation]];
    EXPECT(copy.onDevice);
    EXPECT([copy.simulatorID isEqualToString:target.simulatorID]);

    // Targets saved before device support default to the simulator.
    MBTTarget *legacy = [MBTTarget targetWithDictionary:@{@"scheme": @"App", @"simulatorID": @"X"}];
    EXPECT(!legacy.onDevice);
}

static void test_physical_devices_filter(void) {
    NSArray *devices = @[
        @{@"name": @"iPhone 17", @"deviceId": @"SIM-1", @"isAvailable": @YES},
        @{@"name": @"Phone", @"deviceId": @"HW-1", @"isAvailable": @YES},
        @{@"name": @"Old iPad", @"deviceId": @"HW-2", @"isAvailable": @NO},
        @{@"name": @"No id", @"isAvailable": @YES},
        @"garbage",
    ];
    NSArray *simulators = @[ @{@"name": @"iPhone 17", @"simulatorId": @"SIM-1"} ];
    NSArray *result = [MBTCLI physicalDevicesFrom:devices excludingSimulators:simulators];
    EXPECT(result.count == 1);
    EXPECT([result.firstObject[@"deviceId"] isEqualToString:@"HW-1"]);
}

static void test_first_runnable_target(void) {
    MBTProject *project = [MBTProject projectWithPath:@"/tmp/A.xcodeproj"];
    EXPECT([project firstRunnableTarget] == nil);

    MBTTarget *aggregate = [project addTargetWithScheme:@"Aggregate"];
    aggregate.probed = YES;
    EXPECT(aggregate.platform.length == 0);
    EXPECT([project firstRunnableTarget] == nil);

    // Not probed yet: unknown, must not be picked.
    MBTTarget *pending = [project addTargetWithScheme:@"Pending"];
    EXPECT([project firstRunnableTarget] == nil);

    MBTTarget *app = [project addTargetWithScheme:@"App"];
    app.platform = @"ios";
    app.probed = YES;
    EXPECT([project firstRunnableTarget] == app);

    MBTTarget *mac = [project addTargetWithScheme:@"Mac"];
    mac.platform = @"macos";
    mac.probed = YES;
    EXPECT([project firstRunnableTarget] == app);
}

int main(void) {
    @autoreleasepool {
        test_parses_build_stage();
        test_parses_compiler_diagnostic();
        test_parses_phase_and_summary();
        test_ignores_garbage();
        test_project_targets();
        test_store_add_and_order();
        test_store_migrates_legacy_single_scheme();
        test_recent_simulators();
        test_platform_detection();
        test_diagnostic_display_filter();
        test_location_with_column();
        test_target_round_trip();
        test_first_runnable_target();
        test_device_target_round_trip();
        test_physical_devices_filter();
        test_line_buffer_splits_across_chunks();
        printf("%d checks, %d failures\n", gChecks, gFailures);
        return gFailures > 0 ? 1 : 0;
    }
}
