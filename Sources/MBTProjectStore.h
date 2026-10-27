#import <Foundation/Foundation.h>
#import "MBTProject.h"

@interface MBTProjectStore : NSObject
@property (nonatomic, readonly) NSArray<MBTProject *> *projects;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (MBTProject *)addProjectAtPath:(NSString *)path;
- (void)touchProjectAtPath:(NSString *)path;
- (void)removeProjectAtPath:(NSString *)path;
- (MBTProject *)projectAtPath:(NSString *)path;

/// Simulator favourites are global, not per project.
@property (nonatomic, readonly) NSArray<NSString *> *favoriteSimulatorIDs;
- (BOOL)isSimulatorFavorite:(NSString *)simulatorID;
- (void)toggleSimulatorFavorite:(NSString *)simulatorID;

- (void)save;
@end
