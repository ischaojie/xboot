#import "MBTProjectStore.h"

static NSString *const kProjectsKey = @"projects";
static NSString *const kRecentKey = @"recentSimulators";
static const NSUInteger kRecentLimit = 3;

@interface MBTProjectStore ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSMutableArray<MBTProject *> *items;
@property (nonatomic, strong) NSMutableArray<NSString *> *recent;
@end

@implementation MBTProjectStore

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _items = [NSMutableArray array];
        _recent = [NSMutableArray array];
        [self load];
    }
    return self;
}

- (void)load {
    // One-time cleanup of the favourites list this replaces.
    [self.defaults removeObjectForKey:@"favoriteSimulators"];

    for (id entry in [self.defaults arrayForKey:kRecentKey]) {
        if ([entry isKindOfClass:[NSString class]]) [self.recent addObject:entry];
    }

    NSArray *raw = [self.defaults arrayForKey:kProjectsKey];
    for (id entry in raw) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        [self.items addObject:[MBTProject projectWithDictionary:entry]];
    }
}

- (NSArray<MBTProject *> *)projects {
    return [self.items copy];
}

- (MBTProject *)projectAtPath:(NSString *)path {
    for (MBTProject *p in self.items) {
        if ([p.path isEqualToString:path]) return p;
    }
    return nil;
}

- (MBTProject *)addProjectAtPath:(NSString *)path {
    MBTProject *existing = [self projectAtPath:path];
    if (existing) {
        [self touchProjectAtPath:path];
        return existing;
    }
    MBTProject *project = [MBTProject projectWithPath:path];
    [self.items insertObject:project atIndex:0];
    [self save];
    return project;
}

- (void)touchProjectAtPath:(NSString *)path {
    MBTProject *project = [self projectAtPath:path];
    if (!project) return;
    project.lastUsed = [NSDate date];
    [self.items removeObjectIdenticalTo:project];
    [self.items insertObject:project atIndex:0];
    [self save];
}

- (void)removeProjectAtPath:(NSString *)path {
    MBTProject *project = [self projectAtPath:path];
    if (!project) return;
    [self.items removeObjectIdenticalTo:project];
    [self save];
}

- (NSArray<NSString *> *)recentSimulatorIDs {
    return [self.recent copy];
}

- (void)recordSimulatorUse:(NSString *)simulatorID {
    if (!simulatorID.length) return;
    [self.recent removeObject:simulatorID];
    [self.recent insertObject:simulatorID atIndex:0];
    while (self.recent.count > kRecentLimit) {
        [self.recent removeLastObject];
    }
    [self.defaults setObject:[self.recent copy] forKey:kRecentKey];
    [self.defaults synchronize];
}

- (void)save {
    NSMutableArray *raw = [NSMutableArray arrayWithCapacity:self.items.count];
    for (MBTProject *project in self.items) {
        [raw addObject:[project dictionaryRepresentation]];
    }
    [self.defaults setObject:raw forKey:kProjectsKey];
    [self.defaults synchronize];
}

@end
