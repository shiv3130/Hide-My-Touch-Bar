#import <Cocoa/Cocoa.h>

static void DrawIcon(CGFloat size) {
    NSRect bounds = NSMakeRect(0, 0, size, size);
    CGFloat scale = size / 1024.0;

    NSGradient *background = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.05 green:0.06 blue:0.075 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.14 green:0.16 blue:0.20 alpha:1.0]
    ]];
    NSBezierPath *roundRect = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 56 * scale, 56 * scale)
                                                              xRadius:220 * scale
                                                              yRadius:220 * scale];
    [background drawInBezierPath:roundRect angle:315];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.12] setStroke];
    roundRect.lineWidth = 10 * scale;
    [roundRect stroke];

    NSRect barRect = NSMakeRect(176 * scale, 392 * scale, 672 * scale, 178 * scale);
    NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:70 * scale yRadius:70 * scale];
    NSGradient *barGradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.06 green:0.08 blue:0.10 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.30 green:0.39 blue:0.48 alpha:1.0]
    ]];
    [barGradient drawInBezierPath:bar angle:0];

    [[NSColor colorWithCalibratedRed:0.44 green:0.83 blue:1.00 alpha:0.95] setStroke];
    bar.lineWidth = 12 * scale;
    [bar stroke];

    NSBezierPath *shine = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(218 * scale, 512 * scale, 588 * scale, 24 * scale)
                                                          xRadius:12 * scale
                                                          yRadius:12 * scale];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.42] setFill];
    [shine fill];

    NSBezierPath *lens = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(428 * scale, 342 * scale, 168 * scale, 168 * scale)];
    [[NSColor colorWithCalibratedRed:0.49 green:0.90 blue:1.00 alpha:1.0] setFill];
    [lens fill];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.92] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(475 * scale, 389 * scale, 74 * scale, 74 * scale)] fill];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.88] setStroke];
    NSBezierPath *slash = [NSBezierPath bezierPath];
    [slash moveToPoint:NSMakePoint(306 * scale, 264 * scale)];
    [slash lineToPoint:NSMakePoint(718 * scale, 676 * scale)];
    slash.lineWidth = 58 * scale;
    slash.lineCapStyle = NSLineCapStyleRound;
    [slash stroke];

    [[NSColor colorWithCalibratedRed:0.02 green:0.04 blue:0.06 alpha:0.92] setStroke];
    NSBezierPath *innerSlash = [NSBezierPath bezierPath];
    [innerSlash moveToPoint:NSMakePoint(325 * scale, 283 * scale)];
    [innerSlash lineToPoint:NSMakePoint(699 * scale, 657 * scale)];
    innerSlash.lineWidth = 24 * scale;
    innerSlash.lineCapStyle = NSLineCapStyleRound;
    [innerSlash stroke];
}

static void SavePNG(NSString *path, CGFloat pointSize, CGFloat pixelSize) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(pixelSize, pixelSize)];
    [image lockFocus];
    DrawIcon(pixelSize);
    [image unlockFocus];

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [data writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"build/Icon.iconset";
        NSArray<NSDictionary *> *icons = @[
            @{@"name": @"icon_16x16.png", @"points": @16, @"pixels": @16},
            @{@"name": @"icon_16x16@2x.png", @"points": @16, @"pixels": @32},
            @{@"name": @"icon_32x32.png", @"points": @32, @"pixels": @32},
            @{@"name": @"icon_32x32@2x.png", @"points": @32, @"pixels": @64},
            @{@"name": @"icon_128x128.png", @"points": @128, @"pixels": @128},
            @{@"name": @"icon_128x128@2x.png", @"points": @128, @"pixels": @256},
            @{@"name": @"icon_256x256.png", @"points": @256, @"pixels": @256},
            @{@"name": @"icon_256x256@2x.png", @"points": @256, @"pixels": @512},
            @{@"name": @"icon_512x512.png", @"points": @512, @"pixels": @512},
            @{@"name": @"icon_512x512@2x.png", @"points": @512, @"pixels": @1024}
        ];

        for (NSDictionary *icon in icons) {
            NSString *path = [base stringByAppendingPathComponent:icon[@"name"]];
            SavePNG(path, [icon[@"points"] doubleValue], [icon[@"pixels"] doubleValue]);
        }
    }
    return 0;
}
