#import <Foundation/Foundation.h>
@interface Person : NSObject { NSString *_name; int _age; }
@property (nonatomic, copy) NSString *name; @property (nonatomic) int age;
- (instancetype)initWithName:(NSString *)n age:(int)a;
@end
@implementation Person
@synthesize name = _name; @synthesize age = _age;
- (instancetype)initWithName:(NSString *)n age:(int)a { if ((self = [super init])) { _name = [n copy]; _age = a; } return self; }
- (NSString *)description { return [NSString stringWithFormat:@"<Person %@ %d>", _name, _age]; }
- (void)dealloc { [_name release]; [super dealloc]; }
@end
int main(void) {
  @autoreleasepool {
    NSArray *a = @[@"banana", @"apple", @"cherry"];
    NSArray *sorted = [a sortedArrayUsingSelector:@selector(compare:)];
    printf("%s\n", [[sorted componentsJoinedByString:@","] UTF8String]);
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"one"] = @1; d[@"two"] = @2.5; d[@"three"] = @"3";
    NSArray *keys = [[d allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *k in keys) printf("%s=%s\n", [k UTF8String], [[d[k] description] UTF8String]);
    NSString *s = @"Hello, World";
    printf("%lu %s %s\n", (unsigned long)[s length], [[s uppercaseString] UTF8String], [[s substringWithRange:NSMakeRange(7, 5)] UTF8String]);
    printf("%d %d\n", [s hasPrefix:@"Hello"], [s rangeOfString:@"World"].location == 7);
    printf("%s\n", [[[s componentsSeparatedByString:@", "] description] UTF8String]);
    NSNumber *n = @42; printf("%d %.1f %s\n", [n intValue], [@3.14 doubleValue], [[n stringValue] UTF8String]);
    Person *p = [[Person alloc] initWithName:@"Ada" age:36]; printf("%s\n", [[p description] UTF8String]);
    [p setValue:@"Grace" forKey:@"name"]; printf("%s %d\n", [[p valueForKey:@"name"] UTF8String], [[p valueForKey:@"age"] intValue]);
    [p release];
    NSData *data = [@"binary" dataUsingEncoding:NSUTF8StringEncoding]; printf("%lu\n", (unsigned long)[data length]);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"xef_fnd.txt"];
    [@"file contents\nline2" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *back = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    printf("%lu %d\n", (unsigned long)[back length], [[NSFileManager defaultManager] fileExistsAtPath:path]);
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    printf("size=%llu\n", [attrs fileSize]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:86400]; printf("%.0f\n", [date timeIntervalSince1970]);
    NSDateFormatter *f = [[NSDateFormatter alloc] init]; [f setDateFormat:@"yyyy-MM-dd"]; [f setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    printf("%s\n", [[f stringFromDate:date] UTF8String]); [f release];
    NSSet *set = [NSSet setWithObjects:@1, @2, @2, @3, nil]; printf("%lu\n", (unsigned long)[set count]);
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'b'"]; printf("%s\n", [[[a filteredArrayUsingPredicate:pred] description] UTF8String]);
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"k": @[@1, @2]} options:0 error:nil];
    printf("%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    id obj = [NSJSONSerialization JSONObjectWithData:[@"{\"a\":[1,2,{\"b\":true}]}" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    printf("%s\n", [[obj description] UTF8String]);
    printf("%s\n", [[[NSProcessInfo processInfo] processName] UTF8String]);
    NSCharacterSet *cs = [NSCharacterSet decimalDigitCharacterSet]; printf("%d\n", [cs characterIsMember:'7']);
    printf("%s\n", [[@"a b c" stringByReplacingOccurrencesOfString:@" " withString:@"_"] UTF8String]);
  }
  return 0; }
