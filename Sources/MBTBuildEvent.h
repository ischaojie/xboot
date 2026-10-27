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
/// YES for errors worth showing: severity error, and either a source location or
/// a message that is not an xcodebuild continuation line.
@property (nonatomic, readonly) BOOL isDisplayable;
+ (instancetype)eventFromJSONLine:(NSData *)line;
@end
