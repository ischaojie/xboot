#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MBTEventKind) {
    MBTEventKindUnknown = 0,
    MBTEventKindStage,
    MBTEventKindDiagnostic,
    MBTEventKindPhase,
    MBTEventKindSummary,
};

@interface MBTBuildEvent : NSObject
@property (nonatomic, readonly) MBTEventKind kind;
@property (nonatomic, copy) NSString *stage;
@property (nonatomic, copy) NSString *severity;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic) NSInteger lineNumber;
@property (nonatomic, copy) NSString *phase;
@property (nonatomic) BOOL phaseStarted;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) NSInteger durationMs;
+ (instancetype)eventFromJSONLine:(NSData *)line;
@end
