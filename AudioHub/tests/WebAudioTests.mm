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
        // The exact row shown in the menu owns the controls; no detached audio window.
        NSMenu *menu = [NSMenu new];
        NSMenuItem *separator = NSMenuItem.separatorItem; separator.tag = 4; [menu addItem:separator];
        NSMenuItem *output = [[NSMenuItem alloc] initWithTitle:@"输出设备" action:nil keyEquivalent:@""]; output.tag = 5; [menu addItem:output];
        AHWebAudio *hub = [AHWebAudio new]; [hub setUpMenu:menu];
        client.owner = @"profile-one";
        [hub receive:@{@"version":@1,@"type":@"snapshot",@"tabs":@[snapshot]} client:client];
        AHWebRow *menuRow = hub.rows[@"profile-one:7"];
        check(menuRow.menuItem.menu == menu && menuRow.menuItem.view == menuRow.view, @"Web controls embedded in main menu");
        check(hub.emptyItem.hidden && !hub.window, @"No extra audio window or setup text during normal use");
        check([menu indexOfItem:menuRow.menuItem] > [menu indexOfItem:separator] && [menu indexOfItem:menuRow.menuItem] < [menu indexOfItem:output], @"Upstream app and device sections stay intact");
        [menuRow.mute performClick:nil]; check([client.last[@"value"] boolValue], @"Menu mute sends command");
        menuRow.slider.doubleValue = 25; [menuRow volume:menuRow.slider];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.25];
        while (until.timeIntervalSinceNow > 0) [[NSRunLoop mainRunLoop] runMode:NSEventTrackingRunLoopMode beforeDate:until];
        check([client.last[@"action"] isEqual:@"volume"] && [client.last[@"value"] intValue] == 25, @"Volume debounce runs while menu stays open");
        __block BOOL delivered = NO; AHOnMain(^{ delivered = YES; });
        [[NSRunLoop mainRunLoop] runMode:NSEventTrackingRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        check(delivered, @"Snapshots delivered during menu tracking");
        [hub receive:@{@"version":@1,@"type":@"snapshot",@"tabs":@[]} client:client];
        check(!hub.rows.count && !hub.emptyItem.hidden && !menuRow.menuItem.menu, @"Closed tabs removed from menu");
        [hub show:nil]; check(hub.window.contentView.frame.size.height == 220, @"Compact help replaces oversized scrolling window");
        [hub.window close];
        puts("PASS macOS controls: click binding, immediate feedback, stale snapshots, failure, rapid clicks, navigation");
    }
    return 0;
}
