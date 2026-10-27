#import "MBTProject.h"

@implementation MBTProject

+ (instancetype)projectWithPath:(NSString *)path {
    MBTProject *project = [MBTProject new];
    project.path = path;
    project.configuration = @"Debug";
    project.targets = [NSMutableArray array];
    project.lastUsed = [NSDate date];
    return project;
}

- (NSString *)displayName {
    return [[self.path lastPathComponent] stringByDeletingPathExtension];
}

- (MBTTarget *)targetForScheme:(NSString *)scheme {
    for (MBTTarget *target in self.targets) {
        if ([target.scheme isEqualToString:scheme]) return target;
    }
    return nil;
}

- (MBTTarget *)addTargetWithScheme:(NSString *)scheme {
    MBTTarget *existing = [self targetForScheme:scheme];
    if (existing) return existing;
    MBTTarget *target = [MBTTarget targetWithScheme:scheme];
    [self.targets addObject:target];
    return target;
}

- (void)removeTargetWithScheme:(NSString *)scheme {
    MBTTarget *target = [self targetForScheme:scheme];
    if (target) [self.targets removeObjectIdenticalTo:target];
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *targets = [NSMutableArray arrayWithCapacity:self.targets.count];
    for (MBTTarget *target in self.targets) {
        [targets addObject:[target dictionaryRepresentation]];
    }
    return @{
        @"path": self.path ?: @"",
        @"configuration": self.configuration ?: @"Debug",
        @"lastUsed": @([self.lastUsed timeIntervalSince1970]),
        @"targets": targets,
    };
}

+ (instancetype)projectWithDictionary:(NSDictionary *)dict {
    MBTProject *project = [MBTProject new];
    project.path = dict[@"path"];
    project.configuration = dict[@"configuration"] ?: @"Debug";
    project.lastUsed = [NSDate dateWithTimeIntervalSince1970:[dict[@"lastUsed"] doubleValue]];
    project.targets = [NSMutableArray array];

    NSArray *stored = dict[@"targets"];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in stored) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            [project.targets addObject:[MBTTarget targetWithDictionary:entry]];
        }
    } else if ([dict[@"scheme"] length]) {
        // Legacy (single-scheme) project shape.
        [project.targets addObject:[MBTTarget targetWithDictionary:dict]];
    }
    return project;
}

@end
