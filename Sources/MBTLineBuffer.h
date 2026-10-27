#import <Foundation/Foundation.h>

/// Splits a byte stream into newline-delimited chunks, keeping the remainder.
@interface MBTLineBuffer : NSObject
- (NSArray<NSData *> *)appendData:(NSData *)data;
@end
