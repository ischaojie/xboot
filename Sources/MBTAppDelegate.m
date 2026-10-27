#import "MBTAppDelegate.h"
#import "MBTMainWindowController.h"
#import "MBTProjectStore.h"

@interface MBTAppDelegate ()
@property (nonatomic, strong) MBTMainWindowController *windowController;
@property (nonatomic, strong) MBTProjectStore *store;
@end

@implementation MBTAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self installMainMenu];

    self.store = [[MBTProjectStore alloc] initWithDefaults:[NSUserDefaults standardUserDefaults]];
    self.windowController = [[MBTMainWindowController alloc] initWithStore:self.store];
    [self.windowController present];
}

- (void)installMainMenu {
    NSMenu *mainMenu = [NSMenu new];

    NSMenuItem *appItem = [NSMenuItem new];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"About xboot" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide xboot" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit xboot" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *windowItem = [NSMenuItem new];
    NSMenu *windowMenu = [NSMenu new];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];

    [NSApp setMainMenu:mainMenu];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) [self.windowController present];
    return YES;
}

@end
