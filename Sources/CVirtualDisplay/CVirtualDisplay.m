// Shim over the private CGVirtualDisplay API.
//
// The @interface declarations below are re-declared from the publicly published
// class dumps used by other open-source projects, notably BetterDummy
// (https://github.com/waydabber/BetterDummy, MIT License, Copyright (c) 2021
// Istvan T.; see THIRD_PARTY_NOTICES.md). Only the members this tool uses are
// declared. The classes themselves are resolved at runtime from CoreGraphics.

#import <Foundation/Foundation.h>
#import "CVirtualDisplay.h"

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) double refreshRate;
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray *modes;
- (id)init;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) id queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) struct CGPoint whitePoint;
@property(nonatomic) struct CGPoint bluePrimary;
@property(nonatomic) struct CGPoint greenPrimary;
@property(nonatomic) struct CGPoint redPrimary;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) struct CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic) id terminationHandler;
- (id)init;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) unsigned int displayID;
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@end

void *dh_vd_create(const char *name, uint32_t pointsW, uint32_t pointsH, double hz,
                   uint32_t vendorID, uint32_t productID, uint32_t serial,
                   CGDirectDisplayID *outDisplayID) {
    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class dispClass = NSClassFromString(@"CGVirtualDisplay");
    Class setClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descClass || !dispClass || !setClass || !modeClass) return NULL;

    CGVirtualDisplayDescriptor *desc = [[descClass alloc] init];
    desc.queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
    desc.name = [NSString stringWithUTF8String:name];
    // sRGB-ish primaries (same values BetterDummy takes from the Generic RGB profile).
    desc.whitePoint = CGPointMake(0.950, 1.000);
    desc.redPrimary = CGPointMake(0.454, 0.242);
    desc.greenPrimary = CGPointMake(0.353, 0.674);
    desc.bluePrimary = CGPointMake(0.157, 0.084);
    desc.maxPixelsWide = pointsW * 2;
    desc.maxPixelsHigh = pointsH * 2;
    // Pretend to be a 23" panel of this aspect ratio (only affects reported physical size).
    double diag = 23.0 * 25.4;
    double hyp = sqrt((double)pointsW * pointsW + (double)pointsH * pointsH);
    desc.sizeInMillimeters = CGSizeMake(diag * pointsW / hyp, diag * pointsH / hyp);
    desc.vendorID = vendorID;
    desc.productID = productID;
    desc.serialNum = serial;

    CGVirtualDisplay *display = [[dispClass alloc] initWithDescriptor:desc];
    if (!display) return NULL;

    CGVirtualDisplaySettings *settings = [[setClass alloc] init];
    settings.hiDPI = 1;
    settings.modes = @[ [[modeClass alloc] initWithWidth:pointsW height:pointsH refreshRate:hz] ];
    if (![display applySettings:settings]) return NULL;

    if (outDisplayID) *outDisplayID = display.displayID;
    return (void *)CFBridgingRetain(display);
}

void dh_vd_destroy(void *handle) {
    if (handle) CFRelease(handle);
}
