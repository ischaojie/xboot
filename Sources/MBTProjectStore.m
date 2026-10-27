#import "MBTProjectStore.h"

static NSString *const kProjectsKey = @"projects";

@interface MBTProjectStore ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSMutableArray<MBTProject *> *items;
@end

@implementation MBTProjectStore

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _items = [NSMutableArray array];
        [self load];
    }
    return self;
}

- (void)load {
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

- (void)save {
    NSMutableArray *raw = [NSMutableArray arrayWithCapacity:self.items.count];
    for (MBTProject *project in self.items) {
        [raw addObject:[project dictionaryRepresentation]];
    }
    [self.defaults setObject:raw forKey:kProjectsKey];
    [self.defaults synchronize];
}

@end
