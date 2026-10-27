#import <Cocoa/Cocoa.h>
#import "MBTProjectStore.h"

@interface MBTMainWindowController : NSWindowController
- (instancetype)initWithStore:(MBTProjectStore *)store;
- (void)present;
@end
