/* GameController.framework for xef-osx: no game controllers are ever connected (input comes through the
 * HID/X11 paths), but the API answers like a Mac without controllers so apps (SDL) keep running. */
#import <Foundation/Foundation.h>
#include <math.h>

NSString *const GCControllerDidConnectNotification = @"GCControllerDidConnectNotification";
NSString *const GCControllerDidDisconnectNotification = @"GCControllerDidDisconnectNotification";
NSString *const GCControllerDidBecomeCurrentNotification = @"GCControllerDidBecomeCurrentNotification";
NSString *const GCControllerDidStopBeingCurrentNotification = @"GCControllerDidStopBeingCurrentNotification";
NSString *const GCKeyboardDidConnectNotification = @"GCKeyboardDidConnectNotification";
NSString *const GCKeyboardDidDisconnectNotification = @"GCKeyboardDidDisconnectNotification";
NSString *const GCMouseDidConnectNotification = @"GCMouseDidConnectNotification";
NSString *const GCMouseDidDisconnectNotification = @"GCMouseDidDisconnectNotification";
NSString *const GCMouseDidBecomeCurrentNotification = @"GCMouseDidBecomeCurrentNotification";
NSString *const GCMouseDidStopBeingCurrentNotification = @"GCMouseDidStopBeingCurrentNotification";
const float GCHapticDurationInfinite = INFINITY;
NSString *const GCHapticsLocalityAll = @"All";
NSString *const GCHapticsLocalityDefault = @"Default";
NSString *const GCHapticsLocalityHandles = @"Handles";
NSString *const GCHapticsLocalityLeftHandle = @"Left Handle";
NSString *const GCHapticsLocalityRightHandle = @"Right Handle";
NSString *const GCHapticsLocalityTriggers = @"Triggers";
NSString *const GCHapticsLocalityLeftTrigger = @"Left Trigger";
NSString *const GCHapticsLocalityRightTrigger = @"Right Trigger";
#define GC_INPUT(n, s) NSString *const GCInput##n = @s;
GC_INPUT(ButtonA, "Button A") GC_INPUT(ButtonB, "Button B") GC_INPUT(ButtonX, "Button X") GC_INPUT(ButtonY, "Button Y")
GC_INPUT(ButtonHome, "Button Home") GC_INPUT(ButtonMenu, "Button Menu") GC_INPUT(ButtonOptions, "Button Options")
GC_INPUT(ButtonShare, "Button Share") GC_INPUT(DirectionPad, "Direction Pad") GC_INPUT(LeftShoulder, "Left Shoulder")
GC_INPUT(RightShoulder, "Right Shoulder") GC_INPUT(LeftTrigger, "Left Trigger") GC_INPUT(RightTrigger, "Right Trigger")
GC_INPUT(LeftThumbstick, "Left Thumbstick") GC_INPUT(RightThumbstick, "Right Thumbstick")
GC_INPUT(LeftThumbstickButton, "Left Thumbstick Button") GC_INPUT(RightThumbstickButton, "Right Thumbstick Button")
GC_INPUT(DualShockTouchpadOne, "Touchpad 1") GC_INPUT(DualShockTouchpadTwo, "Touchpad 2") GC_INPUT(DualShockTouchpadButton, "Touchpad Button")
GC_INPUT(XboxPaddleOne, "Paddle 1") GC_INPUT(XboxPaddleTwo, "Paddle 2") GC_INPUT(XboxPaddleThree, "Paddle 3") GC_INPUT(XboxPaddleFour, "Paddle 4")
GC_INPUT(Steering, "Steering") GC_INPUT(Shifter, "Shifter") GC_INPUT(LeftPaddle, "Left Paddle") GC_INPUT(RightPaddle, "Right Paddle")
GC_INPUT(PedalAccelerator, "Accelerator Pedal") GC_INPUT(PedalBrake, "Brake Pedal") GC_INPUT(PedalClutch, "Clutch Pedal")

@interface GCController : NSObject
@end
@implementation GCController
+ (NSArray *)controllers { return @[]; }
+ (id)current { return nil; }
+ (BOOL)shouldMonitorBackgroundEvents { return NO; }
+ (void)setShouldMonitorBackgroundEvents:(BOOL)b {}
+ (BOOL)supportsHIDDevice:(void *)device { return NO; }
+ (void)startWirelessControllerDiscoveryWithCompletionHandler:(void (^)(void))handler { if (handler) handler(); }
+ (void)stopWirelessControllerDiscovery {}
+ (id)controllerWithMicroGamepad { return nil; }
+ (id)controllerWithExtendedGamepad { return nil; }
@end

@interface GCKeyboard : NSObject
@end
@implementation GCKeyboard
+ (id)coalescedKeyboard { return nil; }
@end

@interface GCMouse : NSObject
@end
@implementation GCMouse
+ (NSArray *)mice { return @[]; }
+ (id)current { return nil; }
@end

@interface GCColor : NSObject {
  float _r, _g, _b;
}
@end
@implementation GCColor
- (id)initWithRed:(float)r green:(float)g blue:(float)b {
  if ((self = [super init])) { _r = r; _g = g; _b = b; }
  return self;
}
- (float)red { return _r; }
- (float)green { return _g; }
- (float)blue { return _b; }
@end

#define GC_CLASS(n) @interface n : NSObject @end @implementation n @end
GC_CLASS(GCControllerElement) GC_CLASS(GCControllerAxisInput) GC_CLASS(GCControllerButtonInput)
GC_CLASS(GCControllerDirectionPad) GC_CLASS(GCControllerTouchpad) GC_CLASS(GCDeviceBattery) GC_CLASS(GCDeviceLight)
GC_CLASS(GCDeviceHaptics) GC_CLASS(GCExtendedGamepad) GC_CLASS(GCMicroGamepad) GC_CLASS(GCGamepad) GC_CLASS(GCMotion)
GC_CLASS(GCPhysicalInputProfile) GC_CLASS(GCDualShockGamepad) GC_CLASS(GCDualSenseGamepad) GC_CLASS(GCXboxGamepad)
GC_CLASS(GCDualSenseAdaptiveTrigger) GC_CLASS(GCKeyboardInput) GC_CLASS(GCMouseInput) GC_CLASS(GCEventViewController)
GC_CLASS(GCVirtualController) GC_CLASS(GCVirtualControllerConfiguration) GC_CLASS(GCDirectionalGamepad)
GC_CLASS(GCRacingWheel) GC_CLASS(GCSteeringWheelElement) GC_CLASS(GCGearShifterElement)
