#import <Foundation/Foundation.h>
#import "MBTProject.h"

@interface MBTProjectStore : NSObject
@property (nonatomic, readonly) NSArray<MBTProject *> *projects;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (MBTProject *)addProjectAtPath:(NSString *)path;
- (void)touchProjectAtPath:(NSString *)path;
- (void)removeProjectAtPath:(NSString *)path;
- (MBTProject *)projectAtPath:(NSString *)path;

/// Recently used simulators, most recent first, capped at three. Global.
@property (nonatomic, readonly) NSArray<NSString *> *recentSimulatorIDs;
- (void)recordSimulatorUse:(NSString *)simulatorID;

- (void)save;
@end
