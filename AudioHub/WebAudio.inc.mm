// AudioHub additions, GPL-2.0-or-later. Included once by BGMAppDelegate.mm.
#import <Cocoa/Cocoa.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

static bool AHTransfer(int fd, void *buffer, size_t length, bool writing) {
    char *p = (char *)buffer;
    while (length) {
        ssize_t n = writing ? write(fd, p, length) : read(fd, p, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        p += n; length -= (size_t)n;
    }
    return true;
}

@interface AHClient : NSObject
@property int fd;
@property BOOL closed;
@property(copy) NSString *owner;
@property(strong) dispatch_queue_t output;
- (void)send:(NSDictionary *)message;
@end
@implementation AHClient
- (void)send:(NSDictionary *)message {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    if (!data || data.length > 1048576) return;
    dispatch_async(self.output, ^{
        @synchronized(self) {
            if (self.closed) return;
            uint32_t length = (uint32_t)data.length;
            if (!AHTransfer(self.fd, &length, 4, true) || !AHTransfer(self.fd, (void *)data.bytes, length, true))
                shutdown(self.fd, SHUT_RDWR);
        }
    });
}
@end

@class AHWebAudio;
@interface AHWebRow : NSObject
@property(strong) NSStackView *view;
@property(strong) NSTextField *title;
@property(strong) NSTextField *status;
@property(strong) NSTextField *percent;
@property(strong) NSButton *mute;
@property(strong) NSSlider *slider;
@property(strong) AHClient *client;
@property(copy) NSDictionary *snapshot;
@property(copy) NSString *pending;
@property(copy) NSString *pendingAction;
@property(strong) NSNumber *pendingValue;
@property BOOL acknowledged;
@property BOOL editingVolume;
@property BOOL muted;
- (instancetype)initWithClient:(AHClient *)client;
- (void)update:(NSDictionary *)snapshot;
- (void)complete:(NSDictionary *)message;
- (void)cancel;
@end

@implementation AHWebRow
- (instancetype)initWithClient:(AHClient *)client {
    if ((self = [super init])) {
        self.client = client;
        self.view = [NSStackView new]; self.view.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.view.alignment = NSLayoutAttributeLeading; self.view.spacing = 5;
        self.title = [NSTextField labelWithString:@""]; self.title.lineBreakMode = NSLineBreakByTruncatingTail;
        self.status = [NSTextField labelWithString:@""]; self.status.font = [NSFont systemFontOfSize:11];
        self.status.textColor = NSColor.secondaryLabelColor;
        self.mute = [NSButton buttonWithTitle:@"" target:self action:@selector(toggle:)];
        self.mute.bordered = NO; self.mute.imagePosition = NSImageOnly;
        self.slider = [NSSlider sliderWithValue:100 minValue:0 maxValue:100 target:self action:@selector(volume:)];
        self.slider.continuous = YES;
        self.percent = [NSTextField labelWithString:@"100%"];
        NSStackView *controls = [NSStackView stackViewWithViews:@[self.mute, self.slider, self.percent]];
        [self.view addArrangedSubview:self.title]; [self.view addArrangedSubview:controls]; [self.view addArrangedSubview:self.status];
        [self.view.widthAnchor constraintEqualToConstant:440].active = YES;
        [self.title.widthAnchor constraintEqualToConstant:440].active = YES;
        [self.status.widthAnchor constraintEqualToConstant:440].active = YES;
        [self.slider.widthAnchor constraintEqualToConstant:340].active = YES;
        [self.mute.widthAnchor constraintEqualToConstant:32].active = YES;
    }
    return self;
}
- (void)renderMute {
    self.mute.image = [NSImage imageWithSystemSymbolName:self.muted ? @"speaker.slash.fill" : @"globe" accessibilityDescription:self.muted ? @"恢复声音" : @"静音"];
    self.mute.toolTip = self.muted ? @"恢复声音" : @"静音";
    self.slider.alphaValue = self.muted ? 0.4 : 1;
    self.percent.alphaValue = self.muted ? 0.4 : 1;
}
- (void)update:(NSDictionary *)snapshot {
    if (self.snapshot && ![self.snapshot[@"generation"] isEqual:snapshot[@"generation"]]) [self cancel];
    self.snapshot = snapshot;
    if (self.pending && self.acknowledged) {
        BOOL matches = [self.pendingAction isEqual:@"mute"] ?
            [snapshot[@"muted"] boolValue] == self.pendingValue.boolValue :
            fabs([snapshot[@"volume"] doubleValue] - self.pendingValue.doubleValue) < 0.1;
        if (matches) self.pending = nil;
    }
    self.title.stringValue = [snapshot[@"title"] isKindOfClass:NSString.class] ? snapshot[@"title"] : @"网页";
    self.title.toolTip = self.title.stringValue;
    self.slider.enabled = [snapshot[@"canVolume"] boolValue];
    if (!self.pending) {
        self.muted = [snapshot[@"muted"] boolValue];
        if (!self.editingVolume) self.slider.doubleValue = [snapshot[@"volume"] doubleValue];
        self.percent.stringValue = [NSString stringWithFormat:@"%.0f%%", self.slider.doubleValue];
        self.status.stringValue = [snapshot[@"domain"] isKindOfClass:NSString.class] ? snapshot[@"domain"] : @"";
    }
    [self renderMute];
}
- (void)command:(NSString *)action value:(id)value {
    NSNumber *tabID = self.snapshot[@"id"];
    if (!tabID) return;
    NSString *request = NSUUID.UUID.UUIDString;
    self.pending = request; self.status.stringValue = @"正在设置…";
    self.pendingAction = action; self.pendingValue = value; self.acknowledged = NO;
    [self.client send:@{@"version":@1, @"type":@"command", @"requestId":request,
        @"tabId":tabID, @"generation":self.snapshot[@"generation"] ?: @"",
        @"action":action, @"value":value}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([self.pending isEqual:request]) {
            self.pending = nil;
            if (!self.acknowledged) { [self update:self.snapshot]; self.status.stringValue = @"操作未确认，请重试"; }
        }
    });
}
- (void)toggle:(id)sender {
    (void)sender; self.muted = !self.muted; [self renderMute];
    [self command:@"mute" value:@(self.muted)];
}
- (void)volume:(id)sender {
    (void)sender; self.percent.stringValue = [NSString stringWithFormat:@"%.0f%%", self.slider.doubleValue];
    self.editingVolume = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendVolume) object:nil];
    [self performSelector:@selector(sendVolume) withObject:nil afterDelay:0.12];
}
- (void)sendVolume { self.editingVolume = NO; [self command:@"volume" value:@(self.slider.doubleValue)]; }
- (void)complete:(NSDictionary *)message {
    if (![self.pending isEqual:message[@"requestId"]]) return;
    if (![message[@"ok"] boolValue]) { self.pending = nil; [self update:self.snapshot]; self.status.stringValue = @"设置失败，请检查网页或连接"; }
    else { self.acknowledged = YES; self.status.stringValue = @"已设置"; }
}
- (void)cancel { self.pending = nil; self.editingVolume = NO; [NSObject cancelPreviousPerformRequestsWithTarget:self]; }
@end

@interface AHWebAudio : NSObject
@property(strong) NSWindow *window;
@property(strong) NSStackView *stack;
@property(strong) NSTextField *status;
@property(strong) NSMutableDictionary<NSString *, AHWebRow *> *rows;
@property(strong) NSMutableDictionary<NSString *, AHClient *> *clients;
- (void)startWithMenu:(NSMenu *)menu;
@end

@implementation AHWebAudio
- (void)show:(id)sender {
    (void)sender; [NSApp activateIgnoringOtherApps:YES]; [self.window makeKeyAndOrderFront:nil];
}
- (void)registerHost {
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Microsoft Edge/NativeMessagingHosts"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
    NSString *host = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"AudioHub.NativeHost"];
    NSDictionary *manifest = @{@"name":@"com.audiohub.edge", @"description":@"AudioHub macOS audio bridge", @"path":host,
        @"type":@"stdio", @"allowed_origins":@[@"chrome-extension://jnigagbpbbmanodglofkckaaccknhjfm/"]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:&error];
    if (!data || ![data writeToFile:[directory stringByAppendingPathComponent:@"com.audiohub.edge.json"] options:NSDataWritingAtomic error:&error])
        self.status.stringValue = @"无法注册 Edge 连接，请检查用户目录权限";
}
- (void)openExtension:(id)sender {
    (void)sender;
    NSString *resources = NSBundle.mainBundle.resourcePath;
    if (!resources) return;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[resources stringByAppendingPathComponent:@"edge"]]];
}
- (void)startWithMenu:(NSMenu *)menu {
    self.rows = [NSMutableDictionary new]; self.clients = [NSMutableDictionary new];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,490,540) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO; self.window.title = @"AudioHub · Edge 网页音源"; [self.window center];
    self.stack = [NSStackView new]; self.stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.alignment = NSLayoutAttributeLeading; self.stack.spacing = 16; self.stack.edgeInsets = NSEdgeInsetsMake(18,18,18,18);
    self.status = [NSTextField labelWithString:@"等待 Edge 扩展连接"];
    [self.stack addArrangedSubview:self.status];
    [self.stack addArrangedSubview:[NSButton buttonWithTitle:@"打开扩展文件夹（首次导入 Edge）" target:self action:@selector(openExtension:)]];
    NSTextField *help = [NSTextField wrappingLabelWithString:@"在 Edge 打开 edge://extensions，开启开发人员模式，加载解压缩的扩展。选择上面打开的 edge 文件夹，然后刷新音视频网页。"];
    [help.widthAnchor constraintEqualToConstant:440].active = YES; [self.stack addArrangedSubview:help];
    NSScrollView *scroll = [NSScrollView new]; scroll.hasVerticalScroller = YES;
    scroll.documentView = self.stack; self.window.contentView = scroll;
    [self.stack.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor].active = YES;
    [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor].active = YES;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"AudioHub 网页音源…" action:@selector(show:) keyEquivalent:@""];
    item.target = self; [menu insertItem:item atIndex:0]; [menu insertItem:NSMenuItem.separatorItem atIndex:1];
    [self registerHost]; [self listen];
}
- (void)receive:(NSDictionary *)message client:(AHClient *)client {
    if (![message[@"version"] isEqual:@1]) return;
    if ([message[@"type"] isEqual:@"snapshot"] && [message[@"tabs"] isKindOfClass:NSArray.class]) {
        NSMutableSet *live = [NSMutableSet new];
        for (id entry in message[@"tabs"]) {
            if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isKindOfClass:NSNumber.class]) continue;
            NSString *key = [NSString stringWithFormat:@"%@:%@", client.owner, entry[@"id"]];
            [live addObject:key]; AHWebRow *row = self.rows[key];
            if (!row) { row = [[AHWebRow alloc] initWithClient:client]; self.rows[key] = row; [self.stack addArrangedSubview:row.view]; }
            [row update:entry];
        }
        for (NSString *key in self.rows.allKeys) {
            AHWebRow *row = self.rows[key];
            if (row.client == client && ![live containsObject:key]) { [row cancel]; [self.stack removeArrangedSubview:row.view]; [row.view removeFromSuperview]; [self.rows removeObjectForKey:key]; }
        }
        self.status.stringValue = [NSString stringWithFormat:@"Edge 已连接 · %lu 个网页音源", (unsigned long)self.rows.count];
    } else if ([message[@"type"] isEqual:@"result"]) {
        NSString *key = [NSString stringWithFormat:@"%@:%@", client.owner, message[@"tabId"]];
        [self.rows[key] complete:message];
    }
}
- (void)listen {
    NSString *directory = [NSString stringWithFormat:@"/tmp/audiohub-%u", getuid()];
    struct stat info;
    if (mkdir(directory.fileSystemRepresentation, 0700) != 0 && errno != EEXIST) { self.status.stringValue = @"无法创建本机连接目录"; return; }
    if (lstat(directory.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid() || (info.st_mode & 077) != 0) { self.status.stringValue = @"本机连接目录权限错误"; return; }
    NSString *path = [directory stringByAppendingPathComponent:@"bridge.sock"];
    if (!lstat(path.fileSystemRepresentation, &info)) {
        if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid()) return;
        int probe = socket(AF_UNIX, SOCK_STREAM, 0);
        struct sockaddr_un existing = {}; existing.sun_family = AF_UNIX;
        strlcpy(existing.sun_path, path.fileSystemRepresentation, sizeof(existing.sun_path));
        if (probe >= 0) {
            bool active = connect(probe, (struct sockaddr *)&existing, sizeof(existing)) == 0;
            close(probe);
            if (active) { self.status.stringValue = @"另一个 AudioHub 已运行，请先退出旧版本"; return; }
        }
        unlink(path.fileSystemRepresentation);
    }
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address = {}; address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    if (server < 0 || bind(server, (struct sockaddr *)&address, sizeof(address)) || listen(server, 8)) {
        if (server >= 0) close(server); self.status.stringValue = @"本机连接启动失败"; return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        for (;;) {
            int fd = accept(server,NULL,NULL); if (fd < 0) break;
            uid_t uid; gid_t gid;
            if (getpeereid(fd,&uid,&gid) || uid != getuid()) { close(fd); continue; }
            int noPipe = 1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,sizeof(noPipe));
            AHClient *client = [AHClient new]; client.fd = fd; client.owner = NSUUID.UUID.UUIDString;
            client.output = dispatch_queue_create("audiohub.client",DISPATCH_QUEUE_SERIAL);
            dispatch_async(dispatch_get_main_queue(), ^{ self.clients[client.owner] = client; });
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                for (;;) {
                    @autoreleasepool {
                        uint32_t length = 0;
                        if (!AHTransfer(fd,&length,4,false) || !length || length > 1048576) break;
                        NSMutableData *data = [NSMutableData dataWithLength:length];
                        if (!AHTransfer(fd,data.mutableBytes,length,false)) break;
                        id message = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                        if ([message isKindOfClass:NSDictionary.class]) dispatch_async(dispatch_get_main_queue(), ^{ [self receive:message client:client]; });
                    }
                }
                @synchronized(client) { client.closed = YES; shutdown(fd,SHUT_RDWR); close(fd); }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self receive:@{@"version":@1,@"type":@"snapshot",@"tabs":@[]} client:client];
                    [self.clients removeObjectForKey:client.owner];
                    self.status.stringValue = self.clients.count ? @"部分网页连接已断开" : @"Edge 未连接；等待扩展重连";
                });
            });
        }
        close(server);
    });
}
@end
