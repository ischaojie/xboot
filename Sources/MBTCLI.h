#import <Foundation/Foundation.h>

@interface MBTCLI : NSObject
/// Absolute path of the mobilebuildmcp binary, or nil when not installed.
+ (NSString *)executablePath;
/// Synchronous. Returns scheme names for a .xcodeproj or .xcworkspace path.
+ (NSArray<NSString *> *)fetchSchemesForPath:(NSString *)path error:(NSError **)error;
/// Synchronous. Returns simulator dictionaries with name/simulatorId/state/runtime.
+ (NSArray<NSDictionary *> *)fetchSimulators:(NSError **)error;
/// Synchronous. Flat key/value build settings for one scheme.
+ (NSDictionary<NSString *, NSString *> *)fetchBuildSettingsForPath:(NSString *)path
                                                             scheme:(NSString *)scheme
                                                              error:(NSError **)error;
+ (NSString *)platformFromBuildSettings:(NSDictionary<NSString *, NSString *> *)settings;
@end
