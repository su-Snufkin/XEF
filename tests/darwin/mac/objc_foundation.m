#import <Foundation/Foundation.h>
int main(){ @autoreleasepool{ NSString*s=[NSString stringWithFormat:@"objc %d",7]; NSLog(@"%@",s); printf("%s\n",[s UTF8String]); } }
