#import "MBTMainWindowController.h"
#import "MBTBuildEvent.h"
#import "MBTBuildRunner.h"
#import "MBTCLI.h"
#import "MBTProject.h"
#import "MBTTarget.h"
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static const CGFloat kWindowWidth = 560;
static const CGFloat kRowHeight = 34;

@interface MBTFlippedView : NSView
@end

@implementation MBTFlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Device menu item

/// A menu row with the device name on the left and a clickable star on the right.
@interface MBTDeviceMenuItemView : NSView
@property (nonatomic, readonly, getter=isFavorite) BOOL favorite;
@property (nonatomic, weak) NSPopUpButton *popUp;
@property (nonatomic, copy) void (^onToggleFavorite)(void);
- (instancetype)initWithTitle:(NSString *)title favorite:(BOOL)favorite selected:(BOOL)selected;
@end

@implementation MBTDeviceMenuItemView {
    NSTextField *_label;
    NSButton *_star;
}

- (instancetype)initWithTitle:(NSString *)title favorite:(BOOL)favorite selected:(BOOL)selected {
    self = [super initWithFrame:NSMakeRect(0, 0, 240, 22)];
    if (!self) return nil;
    self.autoresizingMask = NSViewWidthSizable;

    _label = [NSTextField labelWithString:selected ? [@"✓  " stringByAppendingString:title]
                                                   : [@"     " stringByAppendingString:title]];
    _label.font = [NSFont menuFontOfSize:0];
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_label];

    _star = [NSButton new];
    _star.bordered = NO;
    _star.imagePosition = NSImageOnly;
    _star.target = self;
    _star.action = @selector(toggleFavorite:);
    _star.toolTip = @"收藏";
    _star.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_star];

    [NSLayoutConstraint activateConstraints:@[
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_star.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_star.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_star.widthAnchor constraintEqualToConstant:18],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:_star.leadingAnchor constant:-6],
    ]];

    [self setFavorite:favorite];
    return self;
}

- (void)setFavorite:(BOOL)favorite {
    _favorite = favorite;
    NSImage *image = [NSImage imageWithSystemSymbolName:(favorite ? @"star.fill" : @"star")
                              accessibilityDescription:@"收藏"];
    image.template = YES;
    _star.image = image;
    _star.contentTintColor = favorite ? NSColor.systemYellowColor : NSColor.tertiaryLabelColor;
}

- (void)toggleFavorite:(id)sender {
    [self setFavorite:!self.favorite];
    if (self.onToggleFavorite) self.onToggleFavorite();

    // Clicking inside a menu cancels tracking; reopen it so several devices can
    // be pinned in one pass.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPopUpButton *popUp = weakSelf.popUp;
        if (popUp && !popUp.menu.highlightedItem) [popUp performClick:nil];
    });
}

@end

#pragma mark - Row

@interface MBTTargetRow : NSView
@property (nonatomic, strong) MBTTarget *target;
@property (nonatomic, strong) NSPopUpButton *simulatorPopUp;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, copy) void (^onRun)(MBTTarget *target);
@property (nonatomic, copy) void (^onSimulatorPick)(MBTTarget *target, NSDictionary *simulator);
@property (nonatomic, copy) void (^onToggleFavorite)(MBTTarget *target, NSString *simulatorID);
- (instancetype)initWithTarget:(MBTTarget *)target;
- (void)setSimulators:(NSArray<NSDictionary *> *)simulators favorites:(NSSet<NSString *> *)favorites;
- (void)setBusy:(BOOL)busy status:(NSString *)status;
- (void)setIdleStatus:(NSString *)status;
@end

@implementation MBTTargetRow {
    NSTextField *_schemeLabel;
    NSTextField *_platformLabel;
    NSTextField *_statusLabel;
    NSArray<NSDictionary *> *_simulators;
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
    run.bezelColor = NSColor.controlAccentColor;
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
    [self deviceItemClicked:sender.selectedItem];
}

- (NSMenuItem *)menuItemForSimulator:(NSDictionary *)simulator
                            favorite:(BOOL)favorite
                            selected:(BOOL)selected {
    // The title is what NSPopUpButton renders for the selected item; the custom
    // view only replaces how the row looks inside the open menu.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:simulator[@"name"] ?: @"?"
                                                  action:@selector(deviceItemClicked:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = simulator;

    MBTDeviceMenuItemView *view =
        [[MBTDeviceMenuItemView alloc] initWithTitle:simulator[@"name"] ?: @"?"
                                            favorite:favorite
                                            selected:selected];
    NSString *simulatorID = simulator[@"simulatorId"];
    __weak typeof(self) weakSelf = self;
    view.onToggleFavorite = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self.onToggleFavorite) self.onToggleFavorite(self.target, simulatorID);
    };
    view.popUp = self.simulatorPopUp;
    item.view = view;
    return item;
}

- (void)deviceItemClicked:(NSMenuItem *)item {
    NSDictionary *simulator = item.representedObject;
    if (![simulator isKindOfClass:[NSDictionary class]]) return;
    if (self.onSimulatorPick) self.onSimulatorPick(self.target, simulator);
}

- (void)selectCurrentSimulator {
    for (NSMenuItem *item in self.simulatorPopUp.menu.itemArray) {
        NSDictionary *simulator = item.representedObject;
        if (![simulator isKindOfClass:[NSDictionary class]]) continue;
        if ([simulator[@"simulatorId"] isEqualToString:self.target.simulatorID]) {
            [self.simulatorPopUp selectItem:item];
            return;
        }
    }
    [self.simulatorPopUp selectItemAtIndex:0];
}

- (void)run:(id)sender {
    if (self.onRun) self.onRun(self.target);
}

- (void)setSimulators:(NSArray<NSDictionary *> *)simulators favorites:(NSSet<NSString *> *)favorites {
    _simulators = simulators;

    NSMenu *menu = [[NSMenu alloc] init];
    NSMutableArray<NSMenuItem *> *favoriteItems = [NSMutableArray array];
    NSMutableArray<NSMenuItem *> *otherItems = [NSMutableArray array];

    for (NSDictionary *simulator in simulators) {
        NSString *simulatorID = simulator[@"simulatorId"] ?: @"";
        BOOL isFavorite = [favorites containsObject:simulatorID];
        BOOL isSelected = [simulatorID isEqualToString:self.target.simulatorID];
        NSMenuItem *item = [self menuItemForSimulator:simulator
                                             favorite:isFavorite
                                             selected:isSelected];
        [(isFavorite ? favoriteItems : otherItems) addObject:item];
    }

    for (NSMenuItem *item in favoriteItems) [menu addItem:item];
    if (favoriteItems.count && otherItems.count) [menu addItem:[NSMenuItem separatorItem]];
    for (NSMenuItem *item in otherItems) [menu addItem:item];

    [self.simulatorPopUp setMenu:menu];
    [self selectCurrentSimulator];
    [self updatePlatformDisplay];
}

- (void)updatePlatformDisplay {
    MBTTarget *target = self.target;
    BOOL runnable = target.platform.length > 0;

    if (!runnable) {
        self.simulatorPopUp.hidden = YES;
        _platformLabel.hidden = NO;
        _platformLabel.stringValue = target.probed ? (target.kindLabel ?: @"不可运行") : @"探测中…";
        [self setRunEnabled:NO];
        return;
    }

    _platformLabel.hidden = !target.isMacOS;
    _platformLabel.stringValue = target.isMacOS ? @"macOS" : @"";
    self.simulatorPopUp.hidden = target.isMacOS;
    [self setRunEnabled:YES];
}

- (void)setRunEnabled:(BOOL)enabled {
    self.runButton.enabled = enabled;
    self.runButton.bezelColor = enabled ? NSColor.controlAccentColor : nil;
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    [self setRunEnabled:!busy];
    if (busy) {
        [self.spinner startAnimation:nil];
        self.runButton.title = @"取消";
        [self setRunEnabled:YES];
    } else {
        [self.spinner stopAnimation:nil];
        self.runButton.title = @"▶ Run";
    }
    [self setStatusText:status];
}

/// Stages change every few hundred milliseconds; a hard swap reads as flicker.
- (void)setStatusText:(NSString *)text {
    NSString *next = text ?: @"";
    if ([_statusLabel.stringValue isEqualToString:next]) return;
    _statusLabel.stringValue = next;
    _statusLabel.alphaValue = 0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.09;
        ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        [_statusLabel.animator setAlphaValue:1];
    }];
}

- (void)fadeOutStatus {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        [_statusLabel.animator setAlphaValue:0];
    } completionHandler:^{
        _statusLabel.stringValue = @"";
        _statusLabel.alphaValue = 1;
    }];
}

- (void)setIdleStatus:(NSString *)status {
    [self setStatusText:status];
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
@property (nonatomic, strong) NSScrollView *rowsScrollView;
@property (nonatomic, strong) NSLayoutConstraint *rowsHeightConstraint;
@property (nonatomic, strong) NSStackView *rootStack;
@property (nonatomic, strong) NSLayoutConstraint *errorHeightConstraint;
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
    window.minSize = NSMakeSize(520, 220);
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

    // Target lists can outgrow the window; scroll instead of clipping.
    MBTFlippedView *rowsDocument = [MBTFlippedView new];
    rowsDocument.translatesAutoresizingMaskIntoConstraints = NO;
    [rowsDocument addSubview:self.rowsStack];

    self.rowsScrollView = [NSScrollView new];
    self.rowsScrollView.documentView = rowsDocument;
    self.rowsScrollView.hasVerticalScroller = YES;
    self.rowsScrollView.autohidesScrollers = YES;
    self.rowsScrollView.drawsBackground = NO;
    self.rowsScrollView.borderType = NSNoBorder;
    [NSLayoutConstraint activateConstraints:@[
        [self.rowsStack.topAnchor constraintEqualToAnchor:rowsDocument.topAnchor],
        [self.rowsStack.leadingAnchor constraintEqualToAnchor:rowsDocument.leadingAnchor],
        [self.rowsStack.trailingAnchor constraintEqualToAnchor:rowsDocument.trailingAnchor],
        [self.rowsStack.bottomAnchor constraintEqualToAnchor:rowsDocument.bottomAnchor],
        [rowsDocument.widthAnchor constraintEqualToAnchor:self.rowsScrollView.contentView.widthAnchor],
    ]];

    // Low priority: the list is the only thing allowed to absorb extra height.
    self.rowsHeightConstraint = [self.rowsScrollView.heightAnchor constraintEqualToConstant:60];
    self.rowsHeightConstraint.priority = NSLayoutPriorityDefaultLow;
    self.rowsHeightConstraint.active = YES;
    [self.rowsScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;

    self.emptyLabel = [NSTextField labelWithString:@"还没有项目。点 ＋ 选择一个 .xcodeproj 或 .xcworkspace。"];
    self.emptyLabel.font = [NSFont systemFontOfSize:12];
    self.emptyLabel.textColor = NSColor.secondaryLabelColor;


    self.errorTextView = [NSTextView new];
    self.errorTextView.editable = NO;
    self.errorTextView.drawsBackground = NO;
    self.errorTextView.font = [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular];
    self.errorTextView.textContainerInset = NSMakeSize(2, 8);

    self.errorScrollView = [NSScrollView new];
    self.errorScrollView.documentView = self.errorTextView;
    self.errorScrollView.hasVerticalScroller = YES;
    self.errorScrollView.autohidesScrollers = YES;
    self.errorScrollView.drawsBackground = NO;
    self.errorScrollView.borderType = NSNoBorder;
    self.errorScrollView.alphaValue = 0;
    self.errorHeightConstraint = [self.errorScrollView.heightAnchor constraintEqualToConstant:80];
    self.errorHeightConstraint.active = YES;

    // The error pane lives outside the stack: inside it, a changing height made
    // the stack redistribute space and the rows jump.
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        toolbar, self.pathLabel, topSeparator, self.rowsScrollView, self.emptyLabel, bottomSeparator
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];
    self.rootStack = stack;

    self.errorScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.errorScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.errorScrollView.topAnchor constant:-8],

        [self.errorScrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.errorScrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.errorScrollView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],

        [toolbar.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.pathLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [topSeparator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.rowsScrollView.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [bottomSeparator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    // Only the row list may absorb spare height.
    for (NSView *view in stack.arrangedSubviews) {
        if (view == self.rowsScrollView) continue;
        [view setContentHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationVertical];
    }
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

    // xcodebuild can block on a package graph or a stale lock; do not spin forever.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self.project != project || project.targets.count > 0) return;
        self.emptyLabel.stringValue = @"读取超时。确认 mobilebuildmcp 可用后点 ↻ 重试";
    });

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray<NSString *> *schemes = [MBTCLI fetchSchemesForPath:path error:&error];
        if (!schemes.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (self.project != project) return;
                self.emptyLabel.stringValue = error
                    ? @"读取项目失败，请确认 mobilebuildmcp 在 PATH 中"
                    : @"没有找到 scheme：在 Xcode 里把 scheme 设为 Shared，或点 ↻ 重试";
                [self crossfadeView:self.emptyLabel visible:YES];
                [self crossfadeView:self.rowsScrollView visible:NO];
                [self resizeWindowToFit];
            });
            return;
        }

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

- (void)crossfadeView:(NSView *)view visible:(BOOL)visible {
    if (!visible && view.hidden) return;
    if (visible) {
        if (!view.hidden && view.alphaValue > 0.99) return;
        view.hidden = NO;
    }
    view.alphaValue = visible ? 0 : 1;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        [view.animator setAlphaValue:(visible ? 1 : 0)];
    } completionHandler:^{
        if (!visible) view.hidden = YES;
    }];
}

- (void)rebuildRows {
    for (NSView *view in self.rowsStack.arrangedSubviews) {
        [self.rowsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    BOOL hasTargets = self.project != nil && self.project.targets.count > 0;
    if (!self.project) {
        self.emptyLabel.stringValue = @"还没有项目。点 ＋ 选择一个 .xcodeproj 或 .xcworkspace。";
        [self crossfadeView:self.emptyLabel visible:YES];
        [self crossfadeView:self.rowsScrollView visible:NO];
        return;
    }
    if (!hasTargets) {
        self.emptyLabel.stringValue = @"正在读取项目结构…（首次可能需要几十秒）";
        [self crossfadeView:self.emptyLabel visible:YES];
        [self crossfadeView:self.rowsScrollView visible:NO];
        return;
    }
    [self crossfadeView:self.emptyLabel visible:NO];
    [self crossfadeView:self.rowsScrollView visible:YES];

    for (MBTTarget *target in self.project.targets) {
        MBTTargetRow *row = [[MBTTargetRow alloc] initWithTarget:target];
        [row setSimulators:self.simulators
                 favorites:[NSSet setWithArray:self.store.favoriteSimulatorIDs]];
        __weak typeof(self) weakSelf = self;
        row.onRun = ^(MBTTarget *t) { [weakSelf runTarget:t]; };
        row.onSimulatorPick = ^(MBTTarget *t, NSDictionary *simulator) {
            __strong typeof(weakSelf) self = weakSelf;
            t.simulatorID = simulator[@"simulatorId"];
            t.simulatorName = simulator[@"name"];
            [self.store save];
        };
        row.onToggleFavorite = ^(MBTTarget *t, NSString *simulatorID) {
            __strong typeof(weakSelf) self = weakSelf;
            [self.store toggleSimulatorFavorite:simulatorID];
            [self rebuildRows];
        };
        [self.rowsStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.rowsStack.widthAnchor].active = YES;
    }
    [self resizeWindowToFit];
}

- (void)updateRowsHeight {
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    CGFloat screenHeight = screen.visibleFrame.size.height;
    // Before the window is on screen, -screen is nil and this would clamp the
    // list to 60pt, which shows a scroller and cuts the last row in half.
    if (!isfinite(screenHeight) || screenHeight < 400) screenHeight = 900;

    CGFloat rows = self.rowsStack.fittingSize.height;
    if (!isfinite(rows) || rows < 1) rows = 60;
    self.rowsHeightConstraint.constant = MIN(rows + 2, MAX(60, screenHeight - 340));
}

- (NSRect)windowFrameFittingContent {
    [self updateRowsHeight];
    [self.window.contentView layoutSubtreeIfNeeded];

    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    CGFloat screenHeight = screen.visibleFrame.size.height;
    if (!isfinite(screenHeight) || screenHeight < 400) screenHeight = 900;

    // Measure the stack, not the content view: the content view is already as
    // tall as the window, so its fitting size never shrinks back.
    CGFloat stackHeight = self.rootStack.fittingSize.height;
    if (!isfinite(stackHeight) || stackHeight < 1) return self.window.frame;
    CGFloat contentHeight = 14 + stackHeight + 8 + self.errorHeightConstraint.constant + 14;
    contentHeight = MIN(MAX(contentHeight, 220), screenHeight - 80);

    NSRect frame = self.window.frame;
    CGFloat chrome = frame.size.height - self.window.contentView.frame.size.height;
    CGFloat newHeight = contentHeight + chrome;
    frame.origin.y += frame.size.height - newHeight;
    frame.size.height = newHeight;
    return frame;
}

- (void)resizeWindowToFit {
    [self.window setFrame:[self windowFrameFittingContent] display:YES];
}

/// The pane owns a fixed slot so the window never changes height during a build;
/// only its contents fade. Resizing it earlier made the rows jump.
- (void)setErrorPaneVisible:(BOOL)visible animated:(BOOL)animated {
    CGFloat alpha = visible ? 1 : 0;
    if (fabs(self.errorScrollView.alphaValue - alpha) < 0.01) return;
    if (!animated) {
        self.errorScrollView.alphaValue = alpha;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = visible ? 0.2 : 0.15;
        ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        [self.errorScrollView.animator setAlphaValue:alpha];
    }];
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

#pragma mark - Run

- (void)runTarget:(MBTTarget *)target {
    if (self.runner.isRunning) return;

    [self.diagnostics removeAllObjects];
    [self renderDiagnostics];
    [self setErrorPaneVisible:NO animated:YES];

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
                [self setErrorPaneVisible:YES animated:YES];
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
    MBTTargetRow *row = self.activeRow;
    [self setRowsEnabled:YES except:nil];
    self.activeRow = nil;

    if (success) {
        [row setBusy:NO status:@"已启动"];
        [self setErrorPaneVisible:NO animated:YES];
        // A permanent "已启动" becomes stale noise; let the row return to rest.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self.runner.isRunning && self.activeRow == nil) [row fadeOutStatus];
        });
    } else {
        [row setBusy:NO
               status:self.diagnostics.count
                          ? [NSString stringWithFormat:@"失败 · %lu 个错误", (unsigned long)self.diagnostics.count]
                          : @"失败"];
        [self setErrorPaneVisible:(self.diagnostics.count > 0) animated:YES];
    }
}

- (void)setRowsEnabled:(BOOL)enabled except:(MBTTargetRow *)active {
    for (MBTTargetRow *row in self.rowsStack.arrangedSubviews) {
        if (![row isKindOfClass:[MBTTargetRow class]] || row == active) continue;
        BOOL runnable = row.target.platform.length > 0;
        [row setRunEnabled:enabled && runnable];
        if (!enabled) {
            row.runButton.toolTip = @"另一个构建正在进行";
        } else if (!runnable) {
            row.runButton.toolTip = @"这个 scheme 不构建可运行的应用";
        } else {
            row.runButton.toolTip = nil;
        }
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
