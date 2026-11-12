// NSSound: loading a WAV, duration, volume, loops, play/stop state, delegate. Real AppKit is the reference (played silently).
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface D : NSObject <NSSoundDelegate> @end
@implementation D - (void)sound:(NSSound *)s didFinishPlaying:(BOOL)ok { P("  didFinishPlaying %d\n", ok); } @end
static NSData *wav(int rate, int frames) {
  NSMutableData *d = [NSMutableData data]; uint32_t dl = frames * 2, v32; uint16_t v16;
#define W32(x) v32 = (x); [d appendBytes:&v32 length:4]
#define W16(x) v16 = (x); [d appendBytes:&v16 length:2]
  [d appendBytes:"RIFF" length:4]; W32(36 + dl); [d appendBytes:"WAVEfmt " length:8]; W32(16); W16(1); W16(1); W32(rate); W32(rate * 2); W16(2); W16(16);
  [d appendBytes:"data" length:4]; W32(dl); [d increaseLengthBy:dl]; return d; }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSData *w = wav(8000, 4000);   // 0.5 s
  NSSound *s = [[NSSound alloc] initWithData:w];
  P("loaded %d duration %.2f volume %.2f loops %d playing %d currentTime %.2f name %s\n", s != nil, s.duration, s.volume, s.loops, s.isPlaying, s.currentTime, s.name ? [s.name UTF8String] : "nil");
  NSSound *bad = [[NSSound alloc] initWithData:[NSData dataWithBytes:"junk" length:4]]; P("bad %d\n", bad != nil);
  NSSound *nf = [[NSSound alloc] initWithContentsOfFile:@"/nonexistent.wav" byReference:YES]; P("missing %d\n", nf != nil);
  s.volume = 0; s.loops = YES; P("volume %.2f loops %d\n", s.volume, s.loops); s.loops = NO;
  D *d = [D new]; s.delegate = d; P("delegate set %d\n", s.delegate == d);
  P("stop before play %d\n", [s stop]);
  P("play %d playing %d\n", [s play], s.isPlaying);
  P("play again %d\n", [s play]);
  P("pause %d resume %d\n", [s pause], [s resume]);
  P("stop %d playing %d\n", [s stop], s.isPlaying);
  P("play2 %d\n", [s play]);
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
  P("after finish playing %d\n", s.isPlaying);
  s.currentTime = 0.25; P("currentTime %.2f\n", s.currentTime);
  s.name = @"beep"; P("name %s byName %d\n", [s.name UTF8String], [NSSound soundNamed:@"beep"] == s);
  P("PASS appkit_sound\n");
  fflush(stdout); _exit(0);
} return 0; }
