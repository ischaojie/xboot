#import "MBTTarget.h"

@implementation MBTTarget

+ (instancetype)targetWithScheme:(NSString *)scheme {
    MBTTarget *target = [MBTTarget new];
    target.scheme = scheme;
    return target;
}

- (BOOL)isMacOS {
    return [self.platform isEqualToString:@"macos"];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"scheme": self.scheme ?: @"",
        @"platform": self.platform ?: @"",
        @"simulatorID": self.simulatorID ?: @"",
        @"simulatorName": self.simulatorName ?: @"",
        @"onDevice": @(self.onDevice),
        @"probed": @(self.probed),
        @"kindLabel": self.kindLabel ?: @"",
    };
}

+ (instancetype)targetWithDictionary:(NSDictionary *)dict {
    MBTTarget *target = [MBTTarget new];
    target.scheme = dict[@"scheme"];
    target.platform = [dict[@"platform"] length] ? dict[@"platform"] : nil;
    target.simulatorID = dict[@"simulatorID"];
    target.simulatorName = dict[@"simulatorName"];
    target.onDevice = [dict[@"onDevice"] boolValue];
    target.probed = [dict[@"probed"] boolValue];
    target.kindLabel = [dict[@"kindLabel"] length] ? dict[@"kindLabel"] : nil;
    return target;
}

@end
