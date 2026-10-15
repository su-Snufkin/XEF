// Apple-only additions to libicucore that CoreFoundation uses (not part of upstream ICU).
#include <unicode/uloc.h>
#include <unicode/udatpg.h>
#include <string.h>

int32_t ualoc_getAppleParent(const char *localeID, char *parent, int32_t parentCapacity, UErrorCode *err) {
    return uloc_getParent(localeID, parent, parentCapacity, err);
}

int32_t uadatpg_remapPatternWithOptions(UDateTimePatternGenerator *dtpg, const UChar *pattern, int32_t patternLength,
                                        uint32_t options, UChar *dest, int32_t destCapacity, UErrorCode *err) {
    (void)dtpg; (void)options;
    if (patternLength < 0) { patternLength = 0; while (pattern[patternLength]) patternLength++; }
    if (patternLength > destCapacity) { if (err) *err = U_BUFFER_OVERFLOW_ERROR; return patternLength; }
    memcpy(dest, pattern, (size_t)patternLength * sizeof(UChar));
    return patternLength;
}
