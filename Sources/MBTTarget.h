#import <Foundation/Foundation.h>

/// One runnable scheme within a project, with its own device preference.
@interface MBTTarget : NSObject
@property (nonatomic, copy) NSString *scheme;
/// "ios" or "macos"; nil when the scheme is not runnable (aggregate, framework).
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, copy) NSString *simulatorID;
@property (nonatomic, copy) NSString *simulatorName;
/// NO until a build-settings probe has run for this scheme.
@property (nonatomic) BOOL probed;
/// Human label for non-runnable targets: "extension", "framework", "aggregate".
@property (nonatomic, copy) NSString *kindLabel;

+ (instancetype)targetWithScheme:(NSString *)scheme;
- (BOOL)isMacOS;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)targetWithDictionary:(NSDictionary *)dict;
@end
