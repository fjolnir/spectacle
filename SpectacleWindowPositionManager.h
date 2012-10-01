#import <Foundation/Foundation.h>

// Next/prev display and lef/right half actions can be combined. Other combinations are undefined
typedef enum {
    SpectacleWindowActionNone            = 0x0,
    SpectacleWindowActionFullscreen      = 0x1,
    SpectacleWindowActionLeftHalf        = 0x2,
    SpectacleWindowActionRightHalf       = 0x4,
    SpectacleWindowActionNextDisplay     = 0x8,
    SpectacleWindowActionPreviousDisplay = 0x10,
} SpectacleWindowAction;

@interface SpectacleWindowPositionManager : NSObject
+ (SpectacleWindowPositionManager *)sharedManager;
- (void)moveFrontMostWindowWithAction:(SpectacleWindowAction)action;
@end
