#import "MBTProjectStore.h"

static NSString *const kProjectsKey = @"projects";
static NSString *const kFavoritesKey = @"favoriteSimulators";

@interface MBTProjectStore ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSMutableArray<MBTProject *> *items;
@property (nonatomic, strong) NSMutableArray<NSString *> *favorites;
@end

@implementation MBTProjectStore

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _items = [NSMutableArray array];
        _favorites = [NSMutableArray array];
        [self load];
    }
    return self;
}

- (void)load {
    for (id entry in [self.defaults arrayForKey:kFavoritesKey]) {
        if ([entry isKindOfClass:[NSString class]]) [self.favorites addObject:entry];
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

- (NSArray<NSString *> *)favoriteSimulatorIDs {
    return [self.favorites copy];
}

- (BOOL)isSimulatorFavorite:(NSString *)simulatorID {
    return simulatorID && [self.favorites containsObject:simulatorID];
}

- (void)toggleSimulatorFavorite:(NSString *)simulatorID {
    if (!simulatorID.length) return;
    if ([self.favorites containsObject:simulatorID]) {
        [self.favorites removeObject:simulatorID];
    } else {
        [self.favorites addObject:simulatorID];
    }
    [self.defaults setObject:[self.favorites copy] forKey:kFavoritesKey];
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
