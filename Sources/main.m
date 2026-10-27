#import <Cocoa/Cocoa.h>
#import "MBTAppDelegate.h"

static MBTAppDelegate *gDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        gDelegate = [MBTAppDelegate new];
        app.delegate = gDelegate;
        [app run];
    }
    return 0;
}
