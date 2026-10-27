#import "MBTLineBuffer.h"

@interface MBTLineBuffer ()
@property (nonatomic, strong) NSMutableData *buffer;
@end

@implementation MBTLineBuffer

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = [NSMutableData data];
    }
    return self;
}

- (NSArray<NSData *> *)appendData:(NSData *)data {
    if (data.length > 0) {
        [self.buffer appendData:data];
    }

    NSMutableArray<NSData *> *lines = [NSMutableArray array];
    const uint8_t *bytes = self.buffer.bytes;
    NSUInteger length = self.buffer.length;
    NSUInteger start = 0;

    for (NSUInteger i = 0; i < length; i++) {
        if (bytes[i] != '\n') continue;
        NSUInteger lineLength = i - start;
        if (lineLength > 0 && bytes[start + lineLength - 1] == '\r') {
            lineLength--;
        }
        [lines addObject:[self.buffer subdataWithRange:NSMakeRange(start, lineLength)]];
        start = i + 1;
    }

    if (start > 0) {
        [self.buffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
    }
    return lines;
}

@end
