/* CoreServices-lite for xef-osx: UCKeyTranslate (Unicode keyboard layout translation) for a fixed US-ANSI layout.
 * The layout data pointer is ignored; keyboardType is irrelevant for ANSI. Dead keys do not exist in this layout. */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>

static const char kBase[128] = {
  [0]='a',[11]='b',[8]='c',[2]='d',[14]='e',[3]='f',[5]='g',[4]='h',[34]='i',[38]='j',[40]='k',[37]='l',[46]='m',
  [45]='n',[31]='o',[35]='p',[12]='q',[15]='r',[1]='s',[17]='t',[32]='u',[9]='v',[13]='w',[7]='x',[16]='y',[6]='z',
  [18]='1',[19]='2',[20]='3',[21]='4',[23]='5',[22]='6',[26]='7',[28]='8',[25]='9',[29]='0',
  [49]=' ',[27]='-',[24]='=',[33]='[',[30]=']',[42]='\\',[41]=';',[39]='\'',[43]=',',[47]='.',[44]='/',[50]='`',
  [82]='0',[83]='1',[84]='2',[85]='3',[86]='4',[87]='5',[88]='6',[89]='7',[91]='8',[92]='9',
  [65]='.',[67]='*',[69]='+',[75]='/',[78]='-',[81]='=' };
static const char kShift[128] = {
  [18]='!',[19]='@',[20]='#',[21]='$',[23]='%',[22]='^',[26]='&',[28]='*',[25]='(',[29]=')',
  [27]='_',[24]='+',[33]='{',[30]='}',[42]='|',[41]=':',[39]='"',[43]='<',[47]='>',[44]='?',[50]='~' };

OSStatus UCKeyTranslate(const UCKeyboardLayout *layout, UInt16 vk, UInt16 action, UInt32 mods, UInt32 kbdType, OptionBits opts,
                        UInt32 *deadKeyState, UniCharCount maxLen, UniCharCount *actualLen, UniChar out[]) {
  if (actualLen) *actualLen = 0;
  if (deadKeyState) *deadKeyState = 0;
  if (!out || !maxLen || !actualLen) return paramErr;
  if (vk >= 128) return paramErr;
  if (action == kUCKeyActionUp) return noErr;   /* key-up produces no characters */
  char c = kBase[vk]; if (!c) return noErr;
  int shift = (mods & 2) != 0 /* shiftKey >> 8 */, caps = (mods & 4) != 0 /* alphaLock >> 8 */;
  if (c >= 'a' && c <= 'z') { if (shift != caps) c -= 32; }
  else if (shift && kShift[vk]) c = kShift[vk];
  out[0] = (UniChar)c; *actualLen = 1; return noErr; }

/* LaunchServices: opening URLs/documents in other applications is not available (SDL_OpenURL reports failure) */
OSStatus LSOpenCFURLRef(CFURLRef url, CFURLRef *launched) { if (launched) *launched = NULL; return -10814; }   /* kLSApplicationNotFoundErr */
const CFStringRef kUTTypeFileURL = CFSTR("public.file-url");
