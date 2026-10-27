#import <Foundation/Foundation.h>
#import "MBTTarget.h"

@interface MBTProject : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *configuration;
@property (nonatomic, strong) NSMutableArray<MBTTarget *> *targets;
@property (nonatomic, strong) NSDate *lastUsed;

+ (instancetype)projectWithPath:(NSString *)path;
- (NSString *)displayName;

- (MBTTarget *)targetForScheme:(NSString *)scheme;
/// The first target that can actually produce a runnable app.
- (MBTTarget *)firstRunnableTarget;
- (MBTTarget *)addTargetWithScheme:(NSString *)scheme;
- (void)removeTargetWithScheme:(NSString *)scheme;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)projectWithDictionary:(NSDictionary *)dict;
@end
