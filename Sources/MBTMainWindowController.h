#import <Cocoa/Cocoa.h>
#import "MBTProjectStore.h"

@interface MBTMainWindowController : NSWindowController
- (instancetype)initWithStore:(MBTProjectStore *)store;
- (void)present;

// Commands forwarded from the main menu.
- (void)runFirstRunnable:(id)sender;
- (void)showLog:(id)sender;
- (void)addProject:(id)sender;
@end
