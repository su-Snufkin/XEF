// NSSpellChecker: misspelling ranges, word counts, ignore / learn, guesses, tags. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSSpellChecker *sc = [NSSpellChecker sharedSpellChecker];
  P("shared %d same %d exists %d\n", sc != nil, sc == [NSSpellChecker sharedSpellChecker], [NSSpellChecker sharedSpellCheckerExists]);
  NSInteger t1 = [NSSpellChecker uniqueSpellDocumentTag], t2 = [NSSpellChecker uniqueSpellDocumentTag]; P("tags distinct %d increasing %d\n", t1 != t2, t2 > t1);
  NSString *s = @"hello wrld this is a tset of speling";
  NSRange r = [sc checkSpellingOfString:s startingAt:0]; P("first misspelling %s\n", [NSStringFromRange(r) UTF8String]);
  r = [sc checkSpellingOfString:s startingAt:NSMaxRange(r)]; P("next %s\n", [NSStringFromRange(r) UTF8String]);
  r = [sc checkSpellingOfString:s startingAt:30]; P("from 30 %s\n", [NSStringFromRange(r) UTF8String]);
  r = [sc checkSpellingOfString:@"all good words here" startingAt:0]; P("clean %s\n", [NSStringFromRange(r) UTF8String]);
  NSInteger wc = 0; r = [sc checkSpellingOfString:s startingAt:0 language:nil wrap:NO inSpellDocumentWithTag:t1 wordCount:&wc]; P("with wordCount: %s count %ld\n", [NSStringFromRange(r) UTF8String], (long)wc);
  r = [sc checkSpellingOfString:s startingAt:34 language:nil wrap:YES inSpellDocumentWithTag:t1 wordCount:&wc]; P("wrap from 34: %s\n", [NSStringFromRange(r) UTF8String]);
  P("countWords %ld\n", (long)[sc countWordsInString:@"one two  three, four." language:nil]);
  [sc ignoreWord:@"wrld" inSpellDocumentWithTag:t1];
  r = [sc checkSpellingOfString:s startingAt:0 language:nil wrap:NO inSpellDocumentWithTag:t1 wordCount:NULL]; P("after ignore (tag) %s\n", [NSStringFromRange(r) UTF8String]);
  r = [sc checkSpellingOfString:s startingAt:0 language:nil wrap:NO inSpellDocumentWithTag:t2 wordCount:NULL]; P("other tag %s\n", [NSStringFromRange(r) UTF8String]);
  P("ignored words %lu\n", (unsigned long)[sc ignoredWordsInSpellDocumentWithTag:t1].count);
  [sc learnWord:@"wrld"]; P("learned %d\n", [sc hasLearnedWord:@"wrld"]);
  r = [sc checkSpellingOfString:@"wrld" startingAt:0]; P("after learn %s\n", [NSStringFromRange(r) UTF8String]);
  [sc unlearnWord:@"wrld"]; P("unlearned %d\n", [sc hasLearnedWord:@"wrld"]);
  NSArray *g = [sc guessesForWordRange:NSMakeRange(6, 4) inString:@"hello wrld" language:nil inSpellDocumentWithTag:0]; P("guesses >0 %d contains world %d\n", g.count > 0, [g containsObject:@"world"]);
  NSArray *c = [sc completionsForPartialWordRange:NSMakeRange(0, 3) inString:@"spe" language:nil inSpellDocumentWithTag:0]; P("completions >0 %d\n", c.count > 0);
  P("languages >0 %d\n", sc.availableLanguages.count > 0);
  [sc closeSpellDocumentWithTag:t1]; P("closed\n");
  P("PASS appkit_spell\n");
  fflush(stdout); _exit(0);
} return 0; }
