// Generates the xboot app icon: a blue rounded tile with a hammer whose head
// ends in a play arrow — build, then run.
//
// Usage: icongen <output.iconset>
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

static const CGFloat kCanvas = 1024.0;

/// Fills a path with rounded corners by stroking it, then filling the inside.
static void FillRoundedPolygon(CGContextRef ctx, CGPathRef path, CGFloat radius) {
    CGContextAddPath(ctx, path);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetLineWidth(ctx, radius * 2);
    CGContextSetStrokeColorWithColor(ctx, [NSColor whiteColor].CGColor);
    CGContextStrokePath(ctx);
    CGContextAddPath(ctx, path);
    CGContextSetFillColorWithColor(ctx, [NSColor whiteColor].CGColor);
    CGContextFillPath(ctx);
}

static void DrawIcon(CGContextRef ctx, CGFloat size) {
    CGContextScaleCTM(ctx, size / kCanvas, size / kCanvas);

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    // Tile
    CGRect tile = CGRectMake(88, 88, 848, 848);
    CGPathRef tilePath = CGPathCreateWithRoundedRect(tile, 190, 190, NULL);
    CGContextAddPath(ctx, tilePath);
    CGContextClip(ctx);

    CGFloat top[] = {0.30, 0.67, 1.00, 1.0};
    CGFloat bottom[] = {0.03, 0.25, 0.75, 1.0};
    CGFloat locations[] = {0.0, 1.0};
    CGColorRef c1 = CGColorCreate(space, top);
    CGColorRef c2 = CGColorCreate(space, bottom);
    CFArrayRef colors = CFArrayCreate(NULL, (const void **)&(CGColorRef[]){c1, c2}, 2, &kCFTypeArrayCallBacks);
    CGGradientRef gradient = CGGradientCreateWithColors(space, colors, locations);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(512, 936), CGPointMake(512, 88), 0);

    // Inner rim keeps the tile edge crisp on light backgrounds.
    CGContextAddPath(ctx, tilePath);
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithWhite:1 alpha:0.22].CGColor);
    CGContextSetLineWidth(ctx, 7);
    CGContextStrokePath(ctx);

    // Glass highlight across the upper half.
    CGFloat shineTop[] = {1.0, 1.0, 1.0, 0.26};
    CGFloat shineBottom[] = {1.0, 1.0, 1.0, 0.0};
    CGColorRef s1 = CGColorCreate(space, shineTop);
    CGColorRef s2 = CGColorCreate(space, shineBottom);
    CFArrayRef shineColors = CFArrayCreate(NULL, (const void **)&(CGColorRef[]){s1, s2}, 2, &kCFTypeArrayCallBacks);
    CGGradientRef shine = CGGradientCreateWithColors(space, shineColors, locations);
    CGContextDrawLinearGradient(ctx, shine, CGPointMake(512, 936), CGPointMake(512, 500), 0);

    CGContextRestoreGState(ctx);
    CGContextSaveGState(ctx);

    // Symbol
    CGContextTranslateCTM(ctx, 512, 512);
    CGContextRotateCTM(ctx, 34 * M_PI / 180.0);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -12), 30,
                                [NSColor colorWithSRGBRed:0 green:0.08 blue:0.35 alpha:0.30].CGColor);

    // Handle: from below the centre up into the head.
    CGRect handle = CGRectMake(-28, -376, 56, 410);
    CGPathRef handlePath = CGPathCreateWithRoundedRect(handle, 28, 28, NULL);

    // Head: a thick hammer block whose right end tapers into a play arrow.
    // The polygon is inset by the rounding radius, which the stroking restores.
    CGMutablePathRef headPolygon = CGPathCreateMutable();
    CGPathMoveToPoint(headPolygon, NULL, -168, 52);
    CGPathAddLineToPoint(headPolygon, NULL, 34, 52);
    CGPathAddLineToPoint(headPolygon, NULL, 118, 0);
    CGPathAddLineToPoint(headPolygon, NULL, 34, -52);
    CGPathAddLineToPoint(headPolygon, NULL, -168, -52);
    CGPathCloseSubpath(headPolygon);

    // Compose both shapes into one layer so the drop shadow follows the merged
    // silhouette instead of each piece separately.
    CGContextBeginTransparencyLayer(ctx, NULL);
    CGContextAddPath(ctx, handlePath);
    CGContextSetFillColorWithColor(ctx, [NSColor whiteColor].CGColor);
    CGContextFillPath(ctx);
    FillRoundedPolygon(ctx, headPolygon, 28);
    CGContextEndTransparencyLayer(ctx);

    CGContextRestoreGState(ctx);

    CGPathRelease(tilePath);
    CGPathRelease(handlePath);
    CGPathRelease(headPolygon);
    CGGradientRelease(gradient);
    CGGradientRelease(shine);
    CFRelease(colors);
    CFRelease(shineColors);
    CGColorRelease(c1);
    CGColorRelease(c2);
    CGColorRelease(s1);
    CGColorRelease(s2);
    CGColorSpaceRelease(space);
}

static void WritePNG(CGImageRef image, NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef destination =
        CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
    if (!destination) return;
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: icongen <output.iconset>\n");
            return 1;
        }
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];

        NSDictionary<NSNumber *, NSArray<NSString *> *> *outputs = @{
            @16: @[ @"icon_16x16.png" ],
            @32: @[ @"icon_16x16@2x.png", @"icon_32x32.png" ],
            @64: @[ @"icon_32x32@2x.png" ],
            @128: @[ @"icon_128x128.png" ],
            @256: @[ @"icon_128x128@2x.png", @"icon_256x256.png" ],
            @512: @[ @"icon_256x256@2x.png", @"icon_512x512.png" ],
            @1024: @[ @"icon_512x512@2x.png" ],
        };

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        for (NSNumber *sizeNumber in outputs) {
            CGFloat size = sizeNumber.doubleValue;
            CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)size, (size_t)size, 8, 0, space,
                                                     (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGContextSetShouldAntialias(ctx, YES);
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            DrawIcon(ctx, size);

            CGImageRef image = CGBitmapContextCreateImage(ctx);
            for (NSString *name in outputs[sizeNumber]) {
                WritePNG(image, [directory stringByAppendingPathComponent:name]);
            }
            CGImageRelease(image);
            CGContextRelease(ctx);
        }
        CGColorSpaceRelease(space);
    }
    return 0;
}
