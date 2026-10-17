#include "../WebAudio.inc.mm"

@interface AHTestClient : AHClient
@property(strong) NSDictionary *last;
@end
@implementation AHTestClient
- (void)send:(NSDictionary *)message { self.last = message; }
@end

static void check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        AHTestClient *client = [AHTestClient new];
        AHWebRow *row = [[AHWebRow alloc] initWithClient:client];
        NSMutableDictionary *snapshot = [@{@"id":@7, @"generation":@"one", @"title":@"Test", @"muted":@NO, @"canVolume":@YES, @"volume":@40} mutableCopy];
        [row update:snapshot];
        [row.mute performClick:nil];
        check(row.muted && [client.last[@"value"] boolValue], @"Immediate mute and command binding");
        [row update:snapshot]; check(row.muted, @"Ignore stale snapshot while pending");
        [row complete:@{@"requestId":client.last[@"requestId"] ?: @"", @"ok":@YES}];
        [row update:snapshot]; check(row.muted, @"Ignore stale snapshot after acknowledgement");
        snapshot[@"muted"] = @YES; [row update:snapshot];
        check(!row.pending && row.muted, @"Confirm matching state");
        [row.mute performClick:nil]; check(!row.muted, @"Immediate restore");
        [row complete:@{@"requestId":client.last[@"requestId"] ?: @"", @"ok":@NO}];
        check(row.muted, @"Rejected operation rolls back");
        [row.mute performClick:nil];
        NSString *first = client.last[@"requestId"];
        [row.mute performClick:nil];
        [row complete:@{@"requestId":first,@"ok":@NO}];
        check(row.muted && row.pending, @"Rapid clicks preserve latest intent");
        snapshot[@"generation"] = @"two"; snapshot[@"muted"] = @NO;
        [row update:snapshot]; check(!row.muted && !row.pending, @"Navigation resets pending state");
        [row cancel];
        puts("PASS macOS controls: click binding, immediate feedback, stale snapshots, failure, rapid clicks, navigation");
    }
    return 0;
}
