#import "SpectacleWindowPositionManager.h"
#import "SpectacleScreenDetection.h"
#import "SpectacleUtilities.h"
#import "SpectacleConstants.h"
#import <ZeroKit/ZeroKitAccessibilityElement.h>

#define SPLITFACTOR (0.6)

@interface ZeroKitAccessibilityElement (Private)
@property(readwrite) AXUIElementRef element;
@end

@interface AccessibilityWindow : ZeroKitAccessibilityElement {
    CGRect _frameCache;
}
@property CGRect frame;
+ (AccessibilityWindow *)withElement:(AXUIElementRef)element;
- (void)setFrame:(CGRect)windowRect inScreenFrame:(CGRect)screenFrame;
@end

#pragma mark -

@interface SpectacleWindowPositionManager (SpectacleWindowPositionManagerPrivate)

- (AccessibilityWindow *)frontMostWindow;

#pragma mark -

- (void)moveWindowRect:(CGRect)windowRect
  visibleFrameOfScreen:(CGRect)visibleFrameOfScreen
frontMostWindowElement:(AccessibilityWindow *)frontMostWindowElement;

#pragma mark -

- (CGRect)resizeWindow:(AccessibilityWindow *)window
   screenVisibleFrame:(CGRect)visibleFrame
    originScreenFrame:(CGRect)originScreenFrame
               action:(SpectacleWindowAction)action;

@end

#pragma mark -

@implementation SpectacleWindowPositionManager

static SpectacleWindowPositionManager *sharedInstance = nil;

+ (id)allocWithZone:(NSZone *)zone
{
    return nil;
}

+ (SpectacleWindowPositionManager *)sharedManager
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[super allocWithZone:nil] init];
    });
    return sharedInstance;
}

#pragma mark -

- (void)moveFrontMostWindowWithAction:(SpectacleWindowAction)action
{
    [self moveWindow:[self frontMostWindow] withAction:action];
}

- (CGRect)visibleFrameOfDisplay:(NSScreen *)screen
{
    CGRect frame = CGRectNull;
    CGRect visibleFrame = CGRectNull;

    NSScreen *mainScreen = [NSScreen mainScreen];
    if(screen && ![screen isEqual:mainScreen]) {
        NSRect mainScreenFrame = [mainScreen frame];
        frame = NSRectToCGRect([screen frame]);
        visibleFrame = NSRectToCGRect([screen visibleFrame]);
        if(visibleFrame.origin.y < 0) {
            frame.origin.y        = -frame.origin.y - frame.size.height + mainScreenFrame.size.height;
            visibleFrame.origin.y = -visibleFrame.origin.y - visibleFrame.size.height + mainScreenFrame.size.height;
        }
    } else if(screen) {
        frame = NSRectToCGRect([screen frame]);
        visibleFrame = frame;
        if([NSMenu menuBarVisible]) {
            CGFloat menuBarHeight = [[NSApp mainMenu] menuBarHeight];
            visibleFrame.origin.y += menuBarHeight;
            visibleFrame.size.height -= menuBarHeight;
        }
    }
    return visibleFrame;
}
- (void)moveWindow:(AccessibilityWindow *)window withAction:(SpectacleWindowAction)action
{
    CGRect frontMostWindowRect = window.frame;
    CGRect previousRect = CGRectNull;
    NSScreen *screenOfDisplay = [SpectacleScreenDetection screenWithAction:action andRect:frontMostWindowRect];
    CGRect visibleFrameOfScreen = [self visibleFrameOfDisplay:screenOfDisplay];
    if(CGRectIsNull(frontMostWindowRect) ||  CGRectIsNull(visibleFrameOfScreen)) {
        NSBeep();
        return;
    }

    previousRect = frontMostWindowRect;
    frontMostWindowRect = [self resizeWindow:window
                          screenVisibleFrame:visibleFrameOfScreen
                           originScreenFrame:visibleFrameOfScreen
                                      action:action];

    if(CGRectEqualToRect(previousRect, frontMostWindowRect) || CGRectIsNull(frontMostWindowRect))
        NSBeep();
}

@end

#pragma mark -

@implementation SpectacleWindowPositionManager (SpectacleWindowPositionManagerPrivate)

- (AccessibilityWindow *)frontMostWindow
{
    ZeroKitAccessibilityElement *systemWideElement = [ZeroKitAccessibilityElement systemWideElement];
    ZeroKitAccessibilityElement *applicationWithFocusElement = [systemWideElement elementWithAttribute:kAXFocusedApplicationAttribute];
    AccessibilityWindow *frontMostWindowElement = nil;

    ZeroKitAccessibilityElement *tmp;
    if(applicationWithFocusElement) {
        tmp = [applicationWithFocusElement elementWithAttribute:kAXFocusedWindowAttribute];
        frontMostWindowElement = [AccessibilityWindow withElement:tmp.element];

        if(!frontMostWindowElement)
            NSLog(@"Invalid accessibility element provided, unable to determine the size and position of the window.");
    } else
        return nil;
    return frontMostWindowElement;
}

#pragma mark -

- (void)moveWindowRect:(CGRect)windowRect
  visibleFrameOfScreen:(CGRect)visibleFrameOfScreen
frontMostWindowElement:(AccessibilityWindow *)frontMostWindowElement
{

    [frontMostWindowElement setFrame:windowRect inScreenFrame:visibleFrameOfScreen];

    CGRect movedWindowRect = frontMostWindowElement.frame;

    if(!CGRectContainsRect(visibleFrameOfScreen, movedWindowRect)) {
        if(movedWindowRect.origin.x + movedWindowRect.size.width > visibleFrameOfScreen.origin.x + visibleFrameOfScreen.size.width) {
            movedWindowRect.origin.x = (visibleFrameOfScreen.origin.x + visibleFrameOfScreen.size.width) - movedWindowRect.size.width;
        } else if(movedWindowRect.origin.x < visibleFrameOfScreen.origin.x)
            movedWindowRect.origin.x = visibleFrameOfScreen.origin.x;

        if(movedWindowRect.origin.y + movedWindowRect.size.height > visibleFrameOfScreen.origin.y + visibleFrameOfScreen.size.height) {
            movedWindowRect.origin.y = (visibleFrameOfScreen.origin.y + visibleFrameOfScreen.size.height) - movedWindowRect.size.height;
        } else if(movedWindowRect.origin.y < visibleFrameOfScreen.origin.y)
            movedWindowRect.origin.y = visibleFrameOfScreen.origin.y;
        [frontMostWindowElement setFrame:movedWindowRect inScreenFrame:visibleFrameOfScreen];
    }
}

#pragma mark -

- (NSMutableArray *)windowsMatchingAction:(SpectacleWindowAction)action withScreenFrame:(CGRect)visibleFrame excluding:(AccessibilityWindow *)excludedWindow
{
    NSMutableArray *result = [NSMutableArray array];
    CFArrayRef cfWindows = NULL;
    AXUIElementRef appEl;
    NSNumber *hidden = nil;
    for(NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if([app.bundleIdentifier isEqualToString:@"com.apple.dashboard.client"])
            continue;

        appEl = AXUIElementCreateApplication([app processIdentifier]);
        AXUIElementCopyAttributeValue(appEl, kAXHiddenAttribute, (CFTypeRef *)&hidden);
        if([hidden boolValue])
            continue;
        AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute, (CFTypeRef*)&cfWindows);
        NSArray *windows = (id)cfWindows;
        if([windows count] == 0)
            continue;
        for(id win_ in windows) {
            AXUIElementRef win = (AXUIElementRef)win_;
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute, (CFTypeRef *)&hidden);
            AccessibilityWindow *window = [AccessibilityWindow withElement:win];
            if([hidden boolValue] || CGRectEqualToRect(excludedWindow.frame, window.frame))
                continue;

            CGRect f = window.frame;
            if(((action & SpectacleWindowActionLeftHalf) && WindowIsLeftAligned(f, SPLITFACTOR, visibleFrame))
            ||((action & SpectacleWindowActionRightHalf) && WindowIsRightAligned(f, SPLITFACTOR, visibleFrame)))
                [result addObject:window];
        }
    }
    return result;
}

- (CGRect)resizeWindow:(AccessibilityWindow *)windowToMove
    screenVisibleFrame:(CGRect)visibleFrame
     originScreenFrame:(CGRect)originScreenFrame
                action:(SpectacleWindowAction)action
{
    CGRect windowRect = windowToMove.frame;
    Boolean canChangeSize;
    AXUIElementIsAttributeSettable(windowToMove.element, (CFStringRef)kAXSizeAttribute, &canChangeSize);
    if(!canChangeSize || !windowToMove)
        return CGRectNull;

    CGFloat xSplit = floor(visibleFrame.size.width*SPLITFACTOR);

    BOOL switchingSides = ((action & SpectacleWindowActionRightHalf)   && WindowIsLeftAligned(windowToMove.frame, SPLITFACTOR, visibleFrame))
                          || ((action & SpectacleWindowActionLeftHalf) && WindowIsRightAligned(windowToMove.frame, SPLITFACTOR, visibleFrame))
                          || MovingToNextOrPreviousDisplay(action)
                          || action & SpectacleWindowActionFullscreen;

    windowRect.origin.y = visibleFrame.origin.y;
    if(action & SpectacleWindowActionRightHalf) {
        windowRect.origin.x = visibleFrame.origin.x + xSplit;
        windowRect.size.width = floor(visibleFrame.size.width * (1.0 - SPLITFACTOR));
    } else if(action & SpectacleWindowActionLeftHalf) {
        windowRect.origin.x = visibleFrame.origin.x;
        windowRect.size.width = xSplit;
    }

    if((action & SpectacleWindowActionLeftHalf) || (action & SpectacleWindowActionRightHalf)) {
        windowRect.size.height = visibleFrame.size.height;

        // Get the list of windows existing in this half
        NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
        CFArrayRef cfWindows = NULL;

        NSMutableArray *involvedWindows = [NSMutableArray array];
        NSMutableArray *windowsToFix = [NSMutableArray array];
        AXUIElementRef appEl;

        NSNumber *hidden = nil;
        for(NSRunningApplication *app in apps) {
            if([app.bundleIdentifier isEqualToString:@"com.apple.dashboard.client"])
                continue;

            appEl = AXUIElementCreateApplication([app processIdentifier]);
            AXUIElementCopyAttributeValue(appEl, kAXHiddenAttribute, (CFTypeRef *)&hidden);
            if([hidden boolValue])
                continue;
            AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute, (CFTypeRef*)&cfWindows);
            NSArray *windows = (id)cfWindows;
            if([windows count] == 0)
                continue;
            for(id win_ in windows) {
                AXUIElementRef win = (AXUIElementRef)win_;
                AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute, (CFTypeRef *)&hidden);
                AccessibilityWindow *window = [AccessibilityWindow withElement:win];
                if([hidden boolValue] || CGRectEqualToRect(windowToMove.frame, window.frame))
                    continue;

                CGRect f = window.frame;
                BOOL onDestSide = ((action & SpectacleWindowActionLeftHalf) && WindowIsLeftAligned(f, SPLITFACTOR, visibleFrame))
                                ||((action & SpectacleWindowActionRightHalf) && WindowIsRightAligned(f, SPLITFACTOR, visibleFrame));
                BOOL onOriginal;
                if(!MovingToNextOrPreviousDisplay(action))
                    onOriginal = (action & SpectacleWindowActionLeftHalf  && WindowIsRightAligned(f, SPLITFACTOR, originScreenFrame))
                                 ||(action & SpectacleWindowActionRightHalf && WindowIsLeftAligned(f, SPLITFACTOR, originScreenFrame));
                else
                    onOriginal = ((action & SpectacleWindowActionLeftHalf) && WindowIsLeftAligned(f, SPLITFACTOR, originScreenFrame))
                               ||((action & SpectacleWindowActionRightHalf) && WindowIsRightAligned(f, SPLITFACTOR, originScreenFrame));
                if(onOriginal) {
                    [windowsToFix addObject:window];
                }
                else if(onDestSide)
                    [involvedWindows addObject:window];
            }
        }
        if([involvedWindows count] > 0) {
            [involvedWindows sortUsingComparator:^NSComparisonResult(AccessibilityWindow *obj1, AccessibilityWindow *obj2) {
                return obj1.frame.origin.y > obj2.frame.origin.y ? NSOrderedDescending : NSOrderedAscending;
            }];

            windowRect.size.height /= [involvedWindows count]+1;
            CGRect rect;
            int i = 1;
            for(AccessibilityWindow *window in involvedWindows) {
                rect = windowRect;
                rect.origin.y += i * rect.size.height;
                [window setFrame:rect inScreenFrame:visibleFrame];
              ++i;
            }
        }
        [self moveWindowRect:windowRect
        visibleFrameOfScreen:visibleFrame
      frontMostWindowElement:windowToMove];

        if(switchingSides && [windowsToFix count] > 0) {
            [windowsToFix sortUsingComparator:^NSComparisonResult(AccessibilityWindow *obj1, AccessibilityWindow *obj2) {
                return obj1.frame.origin.y > obj2.frame.origin.y ? NSOrderedDescending : NSOrderedAscending;
            }];
            int fixAction;
            if(!MovingToNextOrPreviousDisplay(action))
                fixAction = action & SpectacleWindowActionLeftHalf ? SpectacleWindowActionRightHalf : SpectacleWindowActionLeftHalf;
            else
                fixAction = (action & ~SpectacleWindowActionNextDisplay) & ~SpectacleWindowActionPreviousDisplay;
            [self resizeWindow:windowsToFix[0]
            screenVisibleFrame:originScreenFrame
             originScreenFrame:originScreenFrame
                        action:fixAction];
        }
        return windowRect;
    } else if(action == SpectacleWindowActionFullscreen) {
        int prevAction = SpectacleWindowActionNone;
        CGRect f = windowToMove.frame;
        if(WindowIsLeftAligned(f, SPLITFACTOR, visibleFrame))
            prevAction = SpectacleWindowActionLeftHalf;
        else if(WindowIsRightAligned(f, SPLITFACTOR, visibleFrame))
            prevAction = SpectacleWindowActionRightHalf;
        windowRect = visibleFrame;
        
        [self moveWindowRect:windowRect
        visibleFrameOfScreen:visibleFrame
      frontMostWindowElement:windowToMove];
        if(prevAction != SpectacleWindowActionNone) {
            NSMutableArray *windowsToFix = [self windowsMatchingAction:prevAction withScreenFrame:visibleFrame excluding:windowToMove];
            if([windowsToFix count] == 0)
                return windowRect;
            [windowsToFix sortUsingComparator:^NSComparisonResult(AccessibilityWindow *obj1, AccessibilityWindow *obj2) {
                return obj1.frame.origin.y > obj2.frame.origin.y ? NSOrderedDescending : NSOrderedAscending;
            }];
            [self resizeWindow:windowsToFix[0]
            screenVisibleFrame:visibleFrame
             originScreenFrame:visibleFrame
                        action:prevAction];
        }
        return windowRect;
    } else if(MovingToNextOrPreviousDisplay(action)) {
        NSScreen *windowScreen = [SpectacleScreenDetection screenWithAction:SpectacleWindowActionFullscreen andRect:windowToMove.frame];
        NSRect srcVisibleFrame = [self visibleFrameOfDisplay:windowScreen];
        CGFloat windowScrXSplit = floor(srcVisibleFrame.size.width*SPLITFACTOR);

        return [self resizeWindow:windowToMove
               screenVisibleFrame:visibleFrame
                originScreenFrame:srcVisibleFrame
                           action:(windowToMove.frame.origin.x >= windowScrXSplit)
                                  ? SpectacleWindowActionRightHalf | action
                                  : SpectacleWindowActionLeftHalf  | action];
    }
    return windowRect;
}

@end

@implementation AccessibilityWindow
@dynamic frame;
+ (AccessibilityWindow *)withElement:(AXUIElementRef)element
{
    return [[[self alloc] initWithElement:element] autorelease];
}
- (id)initWithElement:(AXUIElementRef)element
{
    if(!(self = [self init]))
        return nil;
    self.element = element;
    return self;
}
- (id)init
{
    if(!(self = [super init]))
        return nil;
    _frameCache = CGRectNull;
    return self;
}
- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:[self class]] && CFEqual([(AccessibilityWindow *)object element], self.element);
}
- (CGRect)frame
{
    if(!CGRectIsNull(_frameCache))
        return _frameCache;
    CFTypeRef windowPositionValue = [self valueOfAttribute:kAXPositionAttribute type:kAXValueCGPointType];
    CFTypeRef windowSizeValue = [self valueOfAttribute:kAXSizeAttribute type:kAXValueCGSizeType];
    CGPoint windowPosition;
    CGSize windowSize;

    AXValueGetValue(windowPositionValue, kAXValueCGPointType, (void *)&windowPosition);
    AXValueGetValue(windowSizeValue, kAXValueCGSizeType, (void *)&windowSize);

    return CGRectMake(windowPosition.x, windowPosition.y, windowSize.width, windowSize.height);
}
- (void)setFrame:(CGRect)windowRect
{
    [self setFrame:windowRect inScreenFrame:CGRectNull];
}
- (void)setFrame:(CGRect)rect inScreenFrame:(CGRect)screenFrame
{
    if(CGRectIsNull(screenFrame)) {
        _frameCache = CGRectNull;
        //NSLog(@">> Sizing:%@", NSStringFromRect(*(NSRect *)&windowRect));
        AXValueRef windowRectPositionRef = AXValueCreate(kAXValueCGPointType, (const void *)&rect.origin);
        AXValueRef windowRectSizeRef = AXValueCreate(kAXValueCGSizeType, (const void *)&rect.size);
        [self setValue:windowRectSizeRef forAttribute:kAXSizeAttribute];
        [self setValue:windowRectPositionRef forAttribute:kAXPositionAttribute];
    } else {
        CGRect curr = self.frame;
        CGRect op1  = (CGRect) {
            { MIN(rect.origin.x, curr.origin.x),     MIN(rect.origin.y, curr.origin.y) },
            { MIN(rect.size.width, curr.size.width), MIN(rect.size.height, curr.size.height) }
        };
//        CGRect op2  = (CGRect) {};
        self.frame  = op1;
        self.frame  = rect;
    }
//    [self setValue:windowRectPositionRef forAttribute:kAXPositionAttribute];
//    [self setValue:windowRectSizeRef forAttribute:kAXSizeAttribute];
}

@end
