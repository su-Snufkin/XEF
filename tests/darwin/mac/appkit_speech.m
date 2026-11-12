// NSSpeechSynthesizer: state, delegate, settings (spoken silently at volume 0). Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface D : NSObject <NSSpeechSynthesizerDelegate> { @public NSMutableArray *log; } @end
@implementation D
- (void)speechSynthesizer:(NSSpeechSynthesizer *)s didFinishSpeaking:(BOOL)ok { [log addObject:[NSString stringWithFormat:@"finished%d", ok]]; }
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSSpeechSynthesizer *s = [[NSSpeechSynthesizer alloc] init];
  P("defaults: volume %g rate>0 %d speaking %d feedback %d voice nonnil %d\n", s.volume, s.rate > 0, s.isSpeaking, s.usesFeedbackWindow, s.voice != nil);
  P("anyAppSpeaking %d voices>0 %d defaultVoice nonnil %d\n", [NSSpeechSynthesizer isAnyApplicationSpeaking], [NSSpeechSynthesizer availableVoices].count > 0, [NSSpeechSynthesizer defaultVoice] != nil);
  D *d = [D new]; d->log = [NSMutableArray array]; s.delegate = d; s.volume = 0; P("volume now %g\n", s.volume);
  s.rate = 400; P("rate %g\n", s.rate);
  P("start %d speaking %d\n", [s startSpeakingString:@"hi"], s.isSpeaking);
  [s stopSpeaking]; P("after stop speaking %d log %s\n", s.isSpeaking, [[d->log componentsJoinedByString:@","] UTF8String]); [d->log removeAllObjects];
  [s startSpeakingString:@"hello there world"];
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:6]; while (s.isSpeaking && [until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  P("finished naturally: speaking %d log %s\n", s.isSpeaking, [[d->log componentsJoinedByString:@","] UTF8String]);
  P("empty string start %d\n", [s startSpeakingString:@""]);
  P("PASS appkit_speech\n");
  fflush(stdout); _exit(0);
} return 0; }
