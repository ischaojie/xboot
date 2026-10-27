#import "MBTMainWindowController.h"
#import "MBTBuildEvent.h"
#import "MBTBuildRunner.h"
#import "MBTCLI.h"
#import "MBTProject.h"
#import "MBTTarget.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static const CGFloat kWindowWidth = 560;
static const CGFloat kRowHeight = 34;

@interface MBTFlippedView : NSView
@end

@implementation MBTFlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Row

@interface MBTTargetRow : NSView
@property (nonatomic, strong) MBTTarget *target;
@property (nonatomic, strong) NSPopUpButton *simulatorPopUp;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, copy) void (^onRun)(MBTTarget *target);
@property (nonatomic, copy) void (^onSimulatorPick)(MBTTarget *target, NSInteger index);
- (instancetype)initWithTarget:(MBTTarget *)target;
- (void)setSimulators:(NSArray<NSDictionary *> *)simulators;
- (void)setBusy:(BOOL)busy status:(NSString *)status;
- (void)setIdleStatus:(NSString *)status;
@end

@implementation MBTTargetRow {
    NSTextField *_schemeLabel;
    NSTextField *_platformLabel;
    NSTextField *_statusLabel;
}

- (instancetype)initWithTarget:(MBTTarget *)target {
    self = [super initWithFrame:NSMakeRect(0, 0, kWindowWidth, kRowHeight)];
    if (!self) return nil;
    _target = target;

    _schemeLabel = [NSTextField labelWithString:target.scheme];
    _schemeLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    _schemeLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_schemeLabel.widthAnchor constraintEqualToConstant:150].active = YES;

    _platformLabel = [NSTextField labelWithString:@"…"];
    _platformLabel.font = [NSFont systemFontOfSize:11];
    _platformLabel.textColor = NSColor.secondaryLabelColor;
    [_platformLabel.widthAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;

    _simulatorPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _simulatorPopUp.controlSize = NSControlSizeSmall;
    _simulatorPopUp.font = [NSFont systemFontOfSize:11];
    _simulatorPopUp.target = self;
    _simulatorPopUp.action = @selector(simulatorChanged:);
    [_simulatorPopUp.widthAnchor constraintEqualToConstant:172].active = YES;

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:10.5];
    _statusLabel.textColor = NSColor.tertiaryLabelColor;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSButton *run = [NSButton buttonWithTitle:@"▶ Run" target:self action:@selector(run:)];
    run.bezelStyle = NSBezelStyleRounded;
    run.controlSize = NSControlSizeSmall;
    run.font = [NSFont systemFontOfSize:11];
    [run.widthAnchor constraintGreaterThanOrEqualToConstant:66].active = YES;
    self.runButton = run;

    self.spinner = [NSProgressIndicator new];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    [self.spinner.widthAnchor constraintEqualToConstant:14].active = YES;

    NSStackView *row = [NSStackView stackViewWithViews:@[
        _schemeLabel, _platformLabel, _simulatorPopUp, _statusLabel, NSView.new, self.spinner, run
    ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.heightAnchor constraintEqualToConstant:kRowHeight],
    ]];

    [self updatePlatformDisplay];
    return self;
}

- (void)simulatorChanged:(NSPopUpButton *)sender {
    if (self.onSimulatorPick) self.onSimulatorPick(self.target, sender.indexOfSelectedItem);
}

- (void)run:(id)sender {
    if (self.onRun) self.onRun(self.target);
}

- (void)setSimulators:(NSArray<NSDictionary *> *)simulators {
    [self.simulatorPopUp removeAllItems];
    for (NSDictionary *simulator in simulators) {
        [self.simulatorPopUp addItemWithTitle:simulator[@"name"] ?: @"?"];
    }
    if (self.target.simulatorName.length) {
        [self.simulatorPopUp selectItemWithTitle:self.target.simulatorName];
    }
    [self invalidateIntrinsicContentSize];
    [self updatePlatformDisplay];
}

- (void)updatePlatformDisplay {
    MBTTarget *target = self.target;
    BOOL runnable = target.platform.length > 0;

    if (!runnable) {
        self.simulatorPopUp.hidden = YES;
        _platformLabel.hidden = NO;
        _platformLabel.stringValue = target.probed ? (target.kindLabel ?: @"不可运行") : @"探测中…";
        self.runButton.enabled = NO;
        return;
    }

    _platformLabel.hidden = !target.isMacOS;
    _platformLabel.stringValue = target.isMacOS ? @"macOS" : @"";
    self.simulatorPopUp.hidden = target.isMacOS;
    self.runButton.enabled = YES;
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    self.runButton.enabled = !busy;
    if (busy) {
        [self.spinner startAnimation:nil];
        self.runButton.title = @"取消";
        self.runButton.enabled = YES;
    } else {
        [self.spinner stopAnimation:nil];
        self.runButton.title = @"▶ Run";
    }
    _statusLabel.stringValue = status ?: @"";
}

- (void)setIdleStatus:(NSString *)status {
    _statusLabel.stringValue = status ?: @"";
}

@end

#pragma mark - Window controller

@interface MBTMainWindowController ()
@property (nonatomic, strong) MBTProjectStore *store;
@property (nonatomic, strong) MBTProject *project;
@property (nonatomic, strong) MBTBuildRunner *runner;
@property (nonatomic, strong) NSMutableArray<MBTBuildEvent *> *diagnostics;
@property (nonatomic, strong) NSArray<NSDictionary *> *simulators;

@property (nonatomic, strong) NSTextField *pathLabel;
@property (nonatomic, strong) NSPopUpButton *projectPopUp;
@property (nonatomic, strong) NSTextField *configLabel;
@property (nonatomic, strong) NSView *rowsContainer;
@property (nonatomic, strong) NSStackView *rowsStack;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSScrollView *errorScrollView;
@property (nonatomic, strong) NSTextView *errorTextView;
@property (nonatomic, strong) MBTTargetRow *activeRow;
@property (nonatomic) BOOL hasPlacedWindow;
@end

@implementation MBTMainWindowController

- (instancetype)initWithStore:(MBTProjectStore *)store {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, 420)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"xboot";
    window.minSize = NSMakeSize(520, 260);
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (!self) return nil;
    _store = store;
    _runner = [MBTBuildRunner new];
    _diagnostics = [NSMutableArray array];
    _simulators = @[];
    [self buildInterface];
    [self reload];
    [self loadSimulators];
    return self;
}

- (void)loadSimulators {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary *> *simulators = [MBTCLI fetchSimulators:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            self.simulators = simulators;
            [self rebuildRows];
        });
    });
}

- (void)present {
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    if (!self.hasPlacedWindow) {
        NSScreen *screen = [NSScreen screens].firstObject ?: [NSScreen mainScreen];
        NSRect visible = screen.visibleFrame;
        NSRect frame = self.window.frame;
        frame.origin.x = round(NSMidX(visible) - NSWidth(frame) / 2);
        frame.origin.y = round(NSMidY(visible) - NSHeight(frame) / 2);
        [self.window setFrame:frame display:NO];
        self.hasPlacedWindow = YES;
    }
    [self.window makeKeyAndOrderFront:nil];
}

#pragma mark - Interface

- (void)buildInterface {
    NSView *content = self.window.contentView;

    self.projectPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.projectPopUp.controlSize = NSControlSizeSmall;
    self.projectPopUp.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.projectPopUp.target = self;
    self.projectPopUp.action = @selector(projectChanged:);
    [self.projectPopUp.widthAnchor constraintGreaterThanOrEqualToConstant:170].active = YES;

    NSButton *add = [NSButton buttonWithTitle:@"＋" target:self action:@selector(addProject:)];
    add.bezelStyle = NSBezelStyleRounded;
    add.controlSize = NSControlSizeSmall;
    add.toolTip = @"添加项目";
    [add.widthAnchor constraintEqualToConstant:26].active = YES;

    NSButton *remove = [NSButton buttonWithTitle:@"－" target:self action:@selector(removeProject:)];
    remove.bezelStyle = NSBezelStyleRounded;
    remove.controlSize = NSControlSizeSmall;
    remove.toolTip = @"移除项目";
    [remove.widthAnchor constraintEqualToConstant:26].active = YES;

    NSButton *refresh = [NSButton buttonWithTitle:@"↻" target:self action:@selector(rediscoverTargets:)];
    refresh.bezelStyle = NSBezelStyleRounded;
    refresh.controlSize = NSControlSizeSmall;
    refresh.toolTip = @"重新探测 targets";
    [refresh.widthAnchor constraintEqualToConstant:26].active = YES;

    self.configLabel = [NSTextField labelWithString:@""];
    self.configLabel.font = [NSFont systemFontOfSize:11];
    self.configLabel.textColor = NSColor.secondaryLabelColor;

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[
        self.projectPopUp, add, remove, refresh, NSView.new, self.configLabel
    ]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.alignment = NSLayoutAttributeCenterY;
    toolbar.spacing = 6;

    self.pathLabel = [NSTextField labelWithString:@""];
    self.pathLabel.font = [NSFont systemFontOfSize:10.5];
    self.pathLabel.textColor = NSColor.tertiaryLabelColor;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    [self.pathLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                   forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSBox *topSeparator = [self separator];
    NSBox *bottomSeparator = [self separator];

    self.rowsStack = [NSStackView new];
    self.rowsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.rowsStack.alignment = NSLayoutAttributeLeading;
    self.rowsStack.spacing = 0;
    self.rowsStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.emptyLabel = [NSTextField labelWithString:@"还没有项目。点 ＋ 选择一个 .xcodeproj 或 .xcworkspace。"];
    self.emptyLabel.font = [NSFont systemFontOfSize:12];
    self.emptyLabel.textColor = NSColor.secondaryLabelColor;


    self.errorTextView = [NSTextView new];
    self.errorTextView.editable = NO;
    self.errorTextView.drawsBackground = NO;
    self.errorTextView.font = [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular];
    self.errorTextView.textContainerInset = NSMakeSize(0, 4);

    self.errorScrollView = [NSScrollView new];
    self.errorScrollView.documentView = self.errorTextView;
    self.errorScrollView.hasVerticalScroller = YES;
    self.errorScrollView.drawsBackground = NO;
    self.errorScrollView.borderType = NSNoBorder;
    self.errorScrollView.hidden = YES;
    [self.errorScrollView.heightAnchor constraintEqualToConstant:120].active = YES;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        toolbar, self.pathLabel, topSeparator, self.rowsStack, self.emptyLabel, bottomSeparator, self.errorScrollView
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [toolbar.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.pathLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [topSeparator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.rowsStack.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [bottomSeparator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.errorScrollView.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
}

- (NSBox *)separator {
    NSBox *box = [NSBox new];
    box.boxType = NSBoxSeparator;
    [box.heightAnchor constraintEqualToConstant:1].active = YES;
    return box;
}

#pragma mark - State

- (void)reload {
    [self.projectPopUp removeAllItems];
    for (MBTProject *project in self.store.projects) {
        [self.projectPopUp addItemWithTitle:[project displayName]];
    }

    if (!self.project || ![self.store.projects containsObject:self.project]) {
        self.project = self.store.projects.firstObject;
    }
    if (self.project) {
        [self.projectPopUp selectItemWithTitle:[self.project displayName]];
        self.pathLabel.stringValue = self.project.path;
        self.configLabel.stringValue = self.project.configuration ?: @"Debug";
    } else {
        self.pathLabel.stringValue = @"";
        self.configLabel.stringValue = @"";
    }

    [self rebuildRows];
    if (self.project) [self syncTargetsForProject:self.project];
}

- (void)syncTargetsForProject:(MBTProject *)project {
    NSString *path = project.path;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *schemes = [MBTCLI fetchSchemesForPath:path error:NULL];
        if (!schemes.count) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self.project != project) return;

            NSMutableArray<MBTTarget *> *merged = [NSMutableArray arrayWithCapacity:schemes.count];
            NSMutableArray<MBTTarget *> *added = [NSMutableArray array];
            for (NSString *scheme in schemes) {
                MBTTarget *existing = [project targetForScheme:scheme];
                if (existing) {
                    [merged addObject:existing];
                    // Targets discovered before kind labels existed need one more probe.
                    if (existing.probed && !existing.platform.length && !existing.kindLabel.length) {
                        [added addObject:existing];
                    }
                } else {
                    MBTTarget *target = [MBTTarget targetWithScheme:scheme];
                    [merged addObject:target];
                    [added addObject:target];
                }
            }
            project.targets = merged;
            [self.store save];
            [self rebuildRows];

            for (MBTTarget *target in added) {
                [self probeTarget:target inProject:project];
            }
        });
    });
}

- (void)probeTarget:(MBTTarget *)target inProject:(MBTProject *)project {
    NSString *path = project.path;
    NSString *scheme = target.scheme;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, NSString *> *settings =
            [MBTCLI fetchBuildSettingsForPath:path scheme:scheme error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            NSString *platform = [MBTCLI platformFromBuildSettings:settings];
            BOOL runnable = platform.length && [settings[@"WRAPPER_EXTENSION"] isEqualToString:@"app"];
            target.platform = runnable ? platform : nil;
            target.kindLabel = runnable ? nil : [self kindLabelForSettings:settings];
            target.probed = YES;
            if (runnable && !target.isMacOS && !target.simulatorID.length) {
                NSDictionary *simulator = [self preferredSimulator];
                target.simulatorID = simulator[@"simulatorId"];
                target.simulatorName = simulator[@"name"];
            }
            [self.store save];
            if (self.project == project) [self rebuildRows];
        });
    });
}

- (void)rebuildRows {
    for (NSView *view in self.rowsStack.arrangedSubviews) {
        [self.rowsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    BOOL hasTargets = self.project != nil && self.project.targets.count > 0;
    if (!self.project) {
        self.emptyLabel.hidden = NO;
        self.emptyLabel.stringValue = @"还没有项目。点 ＋ 选择一个 .xcodeproj 或 .xcworkspace。";
        self.rowsStack.hidden = YES;
        return;
    }
    if (!hasTargets) {
        self.emptyLabel.hidden = NO;
        self.emptyLabel.stringValue = @"正在探测 targets…";
        self.rowsStack.hidden = YES;
        return;
    }
    self.emptyLabel.hidden = YES;
    self.rowsStack.hidden = NO;

    for (MBTTarget *target in self.project.targets) {
        MBTTargetRow *row = [[MBTTargetRow alloc] initWithTarget:target];
        [row setSimulators:self.simulators];
        __weak typeof(self) weakSelf = self;
        row.onRun = ^(MBTTarget *t) { [weakSelf runTarget:t]; };
        row.onSimulatorPick = ^(MBTTarget *t, NSInteger index) {
            [weakSelf pickSimulator:index forTarget:t];
        };
        [self.rowsStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.rowsStack.widthAnchor].active = YES;
    }
    [self resizeWindowToFit];
}

- (void)resizeWindowToFit {
    NSWindow *window = self.window;
    if (!window) return;
    [window.contentView layoutSubtreeIfNeeded];
    CGFloat height = window.contentView.fittingSize.height;
    if (!isfinite(height) || height < 1 || height > 2000) return;
    [window setContentSize:NSMakeSize(kWindowWidth, MIN(MAX(height, 220), 760))];
}

#pragma mark - Actions

- (void)projectChanged:(NSPopUpButton *)sender {
    NSInteger index = sender.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.store.projects.count) return;
    self.project = self.store.projects[(NSUInteger)index];
    [self.store touchProjectAtPath:self.project.path];
    [self rebuildRows];
}

- (void)addProject:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *identifier in @[ @"com.apple.xcode.project", @"com.apple.dt.document.workspace" ]) {
        UTType *type = [UTType typeWithIdentifier:identifier];
        if (type) [types addObject:type];
    }
    panel.allowedContentTypes = types;

    __weak typeof(self) weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        __strong typeof(weakSelf) self = weakSelf;
        MBTProject *project = [self.store addProjectAtPath:panel.URL.path];
        self.project = project;
        [self reload];
        [self syncTargetsForProject:project];
    }];
}

- (void)removeProject:(id)sender {
    if (!self.project) return;
    [self.store removeProjectAtPath:self.project.path];
    self.project = nil;
    [self reload];
}

- (void)rediscoverTargets:(id)sender {
    if (!self.project) return;
    [self syncTargetsForProject:self.project];
}

#pragma mark - Discovery

- (NSString *)kindLabelForSettings:(NSDictionary<NSString *, NSString *> *)settings {
    NSString *productType = settings[@"PRODUCT_TYPE"] ?: @"";
    if ([productType hasSuffix:@"app-extension"]) return @"extension";
    if ([productType hasSuffix:@"framework"]) return @"framework";
    if ([productType hasSuffix:@"bundle"]) return @"bundle";
    if ([productType hasSuffix:@"unit-test-bundle"]) return @"tests";
    NSString *wrapper = settings[@"WRAPPER_EXTENSION"];
    if (wrapper.length) return wrapper;
    return @"aggregate";
}

- (NSDictionary *)preferredSimulator {
    for (NSDictionary *simulator in self.simulators) {
        if ([simulator[@"state"] isEqualToString:@"Booted"] && [simulator[@"name"] hasPrefix:@"iPhone"]) {
            return simulator;
        }
    }
    for (NSDictionary *simulator in self.simulators) {
        if ([simulator[@"name"] hasPrefix:@"iPhone"]) return simulator;
    }
    return self.simulators.firstObject ?: @{};
}

- (void)pickSimulator:(NSInteger)index forTarget:(MBTTarget *)target {
    if (index < 0 || index >= (NSInteger)self.simulators.count) return;
    NSDictionary *simulator = self.simulators[(NSUInteger)index];
    target.simulatorID = simulator[@"simulatorId"];
    target.simulatorName = simulator[@"name"];
    [self.store save];
}

#pragma mark - Run

- (void)runTarget:(MBTTarget *)target {
    if (self.runner.isRunning) return;

    [self.diagnostics removeAllObjects];
    [self renderDiagnostics];
    self.errorScrollView.hidden = YES;

    MBTTargetRow *row = [self rowForTarget:target];
    self.activeRow = row;
    [row setBusy:YES status:@"准备中…"];
    [self setRowsEnabled:NO except:row];

    __weak typeof(self) weakSelf = self;
    self.runner.onEvent = ^(MBTBuildEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf handleEvent:event]; });
    };
    self.runner.onFinish = ^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishWithSuccess:success]; });
    };
    [self.runner runProject:self.project target:target];
}

- (MBTTargetRow *)rowForTarget:(MBTTarget *)target {
    for (MBTTargetRow *row in self.rowsStack.arrangedSubviews) {
        if (![row isKindOfClass:[MBTTargetRow class]]) continue;
        if (row.target == target) return row;
    }
    return nil;
}

- (void)handleEvent:(MBTBuildEvent *)event {
    switch (event.kind) {
        case MBTEventKindStage:
            [self.activeRow setBusy:YES status:[self textForStage:event.stage]];
            break;
        case MBTEventKindPhase:
            if (event.phaseStarted) [self.activeRow setBusy:YES status:[self textForPhase:event.phase]];
            break;
        case MBTEventKindDiagnostic:
            if ([event.severity isEqualToString:@"error"] && [self isDisplayableDiagnostic:event]) {
                [self.diagnostics addObject:event];
                [self renderDiagnostics];
                [self.activeRow setBusy:YES
                                 status:[NSString stringWithFormat:@"%lu 个错误", (unsigned long)self.diagnostics.count]];
            }
            break;
        case MBTEventKindSummary:
            if ([event.status isEqualToString:@"FAILED"]) {
                [self.activeRow setBusy:YES status:@"构建失败"];
            }
            break;
        case MBTEventKindUnknown:
            break;
    }
}

- (void)finishWithSuccess:(BOOL)success {
    if (success) {
        [self.activeRow setBusy:NO status:@"已启动"];
        self.errorScrollView.hidden = YES;
    } else {
        [self.activeRow setBusy:NO
                         status:self.diagnostics.count
                                    ? [NSString stringWithFormat:@"失败 · %lu 个错误", (unsigned long)self.diagnostics.count]
                                    : @"失败"];
        self.errorScrollView.hidden = self.diagnostics.count == 0;
    }
    [self setRowsEnabled:YES except:nil];
    self.activeRow = nil;
}

- (void)setRowsEnabled:(BOOL)enabled except:(MBTTargetRow *)active {
    for (MBTTargetRow *row in self.rowsStack.arrangedSubviews) {
        if (![row isKindOfClass:[MBTTargetRow class]] || row == active) continue;
        row.runButton.enabled = enabled && row.target.platform.length > 0;
    }
}

- (NSString *)firstLineOf:(NSString *)message {
    return [message componentsSeparatedByString:@"\n"].firstObject ?: @"";
}

- (BOOL)isDisplayableDiagnostic:(MBTBuildEvent *)event {
    return event.filePath.length > 0 || ![[self firstLineOf:event.message] hasPrefix:@"|"];
}

- (void)renderDiagnostics {
    NSMutableString *text = [NSMutableString string];
    for (MBTBuildEvent *event in self.diagnostics) {
        NSString *message = [self firstLineOf:event.message];
        NSString *location = event.filePath.length
            ? [NSString stringWithFormat:@"  %@:%ld", [event.filePath lastPathComponent], (long)event.lineNumber]
            : @"";
        [text appendFormat:@"%@\n%@\n\n", message, location];
    }
    self.errorTextView.string = text;
}

- (NSString *)textForStage:(NSString *)stage {
    if ([stage isEqualToString:@"RESOLVING_PACKAGES"]) return @"解析依赖…";
    if ([stage isEqualToString:@"COMPILING"]) return @"编译中…";
    if ([stage isEqualToString:@"LINKING"]) return @"链接中…";
    return @"构建中…";
}

- (NSString *)textForPhase:(NSString *)phase {
    if ([phase isEqualToString:@"boot-simulator"]) return @"启动模拟器…";
    if ([phase isEqualToString:@"install-app"]) return @"安装中…";
    if ([phase isEqualToString:@"launch-app"]) return @"启动 App…";
    return @"运行中…";
}

@end
