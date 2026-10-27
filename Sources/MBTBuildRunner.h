#import <Foundation/Foundation.h>
#import "MBTBuildEvent.h"
#import "MBTProject.h"
#import "MBTTarget.h"

typedef void (^MBTBuildEventHandler)(MBTBuildEvent *event);
typedef void (^MBTBuildFinishHandler)(BOOL success);

@interface MBTBuildRunner : NSObject
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, copy) MBTBuildEventHandler onEvent;
@property (nonatomic, copy) MBTBuildFinishHandler onFinish;
- (void)runProject:(MBTProject *)project target:(MBTTarget *)target;
- (void)cancel;
@end
