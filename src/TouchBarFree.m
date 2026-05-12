#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <ServiceManagement/ServiceManagement.h>

static NSTouchBarItemIdentifier const kTrayIdentifier = @"com.local.touchbarfree.tray";
static NSTouchBarItemIdentifier const kBlankItemIdentifier = @"com.local.touchbarfree.blank";
static NSTouchBarItemIdentifier const kEscapeItemIdentifier = @"com.local.touchbarfree.escape";
static NSString *const kSelectedKeyDefaultsKey = @"SelectedDoubleTapKey";
static NSString *const kFunctionKeyDefaultsKey = @"SelectedFunctionDoubleTapKey";
static NSString *const kFunctionKeysEnabledDefaultsKey = @"FunctionKeysEnabled";
static NSString *const kQuickActionsDefaultsKey = @"QuickActionsEnabled";
static NSString *const kUpdatesDefaultsKey = @"UpdatesEnabled";
static NSString *const kIconThemeDefaultsKey = @"StatusIconTheme";
static NSString *const kNoPhysicalEscapeDefaultsKey = @"NoPhysicalEscape";
static NSString *const kShowEscapeWhenHiddenDefaultsKey = @"ShowEscapeWhenHidden";
static NSString *const kDefaultSelectedKey = @"command";
static NSString *const kDefaultFunctionKey = @"option";
static NSTimeInterval const kDoubleTapInterval = 0.45;

extern void DFRElementSetControlStripPresenceForIdentifier(NSString *identifier, BOOL enabled);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

@interface NSTouchBarItem (PrivateTouchBar)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (PrivateTouchBar)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)dismissSystemModalFunctionBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalFunctionBar:(NSTouchBar *)touchBar;
@end

@interface BlankTouchBarView : NSView
@end

@implementation BlankTouchBarView

- (NSSize)intrinsicContentSize {
    return NSMakeSize(2400, 30);
}

@end

@interface PreferencesBackgroundView : NSView
@end

@implementation PreferencesBackgroundView

- (void)drawRect:(NSRect)dirtyRect {
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.965 green:0.978 blue:0.995 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.925 green:0.945 blue:0.975 alpha:1.0]
    ]];
    [gradient drawInRect:self.bounds angle:270];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.68] setFill];
    NSBezierPath *topGlow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(self.bounds.size.width - 260, self.bounds.size.height - 210, 360, 240)];
    [topGlow fill];

    [[NSColor colorWithCalibratedRed:0.45 green:0.78 blue:1.0 alpha:0.10] setFill];
    NSBezierPath *bottomGlow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-120, -130, 360, 220)];
    [bottomGlow fill];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *toggleItem;
@property (nonatomic, strong) NSCustomTouchBarItem *trayItem;
@property (nonatomic, strong) NSTouchBar *blankTouchBar;
@property (nonatomic, strong) NSWindow *preferencesWindow;
@property (nonatomic, strong) NSView *preferencesContentView;
@property (nonatomic, strong) NSButton *generalTabButton;
@property (nonatomic, strong) NSButton *hotKeysTabButton;
@property (nonatomic, strong) NSButton *launchAtLoginCheckbox;
@property (nonatomic, strong) NSButton *quickActionsCheckbox;
@property (nonatomic, strong) NSButton *updatesCheckbox;
@property (nonatomic, strong) NSButton *functionKeysCheckbox;
@property (nonatomic, strong) NSButton *noPhysicalEscapeCheckbox;
@property (nonatomic, strong) NSButton *showEscapeWhenHiddenCheckbox;
@property (nonatomic, assign) CFMachPortRef eventTap;
@property (nonatomic, assign) CFRunLoopSourceRef eventTapSource;
@property (nonatomic, strong) id fallbackMonitor;
@property (nonatomic, strong) NSTimer *eventTapRetryTimer;
@property (nonatomic, copy) NSString *selectedKey;
@property (nonatomic, copy) NSString *functionKey;
@property (nonatomic, copy) NSString *preferencesTab;
@property (nonatomic, assign) BOOL blankTouchBarShown;
@property (nonatomic, assign) BOOL selectedKeyWasDown;
@property (nonatomic, assign) BOOL functionKeyWasDown;
@property (nonatomic, assign) NSTimeInterval lastTapTime;
@property (nonatomic, assign) NSTimeInterval lastFunctionTapTime;
- (BOOL)installEventTap;
- (void)handleFlags:(CGEventFlags)flags keyCode:(CGKeyCode)keyCode eventType:(CGEventType)type isRepeat:(BOOL)isRepeat;
@end

static CGEventRef touchBarFreeEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    AppDelegate *delegate = (__bridge AppDelegate *)refcon;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (delegate.eventTap != NULL) {
            CGEventTapEnable(delegate.eventTap, true);
        }
        return event;
    }

    if (type == kCGEventFlagsChanged || type == kCGEventKeyDown) {
        CGEventFlags flags = CGEventGetFlags(event);
        CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        BOOL isRepeat = CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0;
        [delegate handleFlags:flags keyCode:keyCode eventType:type isRepeat:isRepeat];
    }

    return event;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self registerDefaultSettings];
    self.selectedKey = [[NSUserDefaults standardUserDefaults] stringForKey:kSelectedKeyDefaultsKey] ?: kDefaultSelectedKey;
    self.functionKey = [[NSUserDefaults standardUserDefaults] stringForKey:kFunctionKeyDefaultsKey] ?: kDefaultFunctionKey;
    self.preferencesTab = @"general";

    [self setUpStatusMenu];
    [self setUpTouchBar];
    [self setUpControlStripButton];
    [self setUpShortcutListener];
    [self requestKeyboardMonitoringPermission];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self dismissBlankTouchBar:nil];

    if ([NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]) {
        [NSTouchBarItem removeSystemTrayItem:self.trayItem];
    }

    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, NO);
    [self removeFallbackMonitor];
    [self.eventTapRetryTimer invalidate];
    self.eventTapRetryTimer = nil;

    if (self.eventTapSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), self.eventTapSource, kCFRunLoopCommonModes);
        CFRelease(self.eventTapSource);
        self.eventTapSource = NULL;
    }

    if (self.eventTap != NULL) {
        CFRelease(self.eventTap);
        self.eventTap = NULL;
    }
}

- (void)setUpStatusMenu {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [self statusIconImage];
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"Touch Bar Free - double-tap %@ to toggle", [self displayNameForKey:self.selectedKey]];
    [self rebuildStatusMenu];
}

- (void)rebuildStatusMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Touch Bar Free"];

    self.toggleItem = [[NSMenuItem alloc] initWithTitle:(self.blankTouchBarShown ? @"Show Touch Bar" : @"Hide Touch Bar") action:@selector(toggleBlankTouchBar:) keyEquivalent:@""];
    self.toggleItem.target = self;
    self.toggleItem.state = self.blankTouchBarShown ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:self.toggleItem];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kQuickActionsDefaultsKey]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Brightness Down" keyType:NX_KEYTYPE_BRIGHTNESS_DOWN]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Brightness Up" keyType:NX_KEYTYPE_BRIGHTNESS_UP]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Keyboard Brightness Down" keyType:NX_KEYTYPE_ILLUMINATION_DOWN]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Keyboard Brightness Up" keyType:NX_KEYTYPE_ILLUMINATION_UP]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Volume Down" keyType:NX_KEYTYPE_SOUND_DOWN]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Volume Up" keyType:NX_KEYTYPE_SOUND_UP]];
        [menu addItem:[self systemKeyMenuItemWithTitle:@"Mute" keyType:NX_KEYTYPE_MUTE]];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..." action:@selector(showPreferences:) keyEquivalent:@","];
    preferencesItem.target = self;
    [menu addItem:preferencesItem];

    NSMenuItem *permissionItem = [[NSMenuItem alloc] initWithTitle:@"Request Keyboard Permission" action:@selector(requestKeyboardMonitoringPermission) keyEquivalent:@""];
    permissionItem.target = self;
    [menu addItem:permissionItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

- (void)registerDefaultSettings {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kSelectedKeyDefaultsKey: kDefaultSelectedKey,
        kFunctionKeyDefaultsKey: kDefaultFunctionKey,
        kFunctionKeysEnabledDefaultsKey: @NO,
        kQuickActionsDefaultsKey: @YES,
        kUpdatesDefaultsKey: @NO,
        kIconThemeDefaultsKey: @"touchbar",
        kNoPhysicalEscapeDefaultsKey: @NO,
        kShowEscapeWhenHiddenDefaultsKey: @NO
    }];
}

- (void)setUpTouchBar {
    self.blankTouchBar = [[NSTouchBar alloc] init];
    self.blankTouchBar.delegate = self;
    self.blankTouchBar.defaultItemIdentifiers = @[ kBlankItemIdentifier ];
    self.blankTouchBar.principalItemIdentifier = kBlankItemIdentifier;
}

- (void)setUpControlStripButton {
    DFRSystemModalShowsCloseBoxWhenFrontMost(NO);

    NSButton *button = [NSButton buttonWithTitle:@"◐" target:self action:@selector(toggleBlankTouchBar:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    button.toolTip = @"Toggle blank Touch Bar";

    self.trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:kTrayIdentifier];
    self.trayItem.view = button;

    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    DFRElementSetControlStripPresenceForIdentifier(kTrayIdentifier, YES);
}

- (void)setUpShortcutListener {
    if ([self installEventTap]) {
        return;
    }

    [self installFallbackMonitor];

    __weak AppDelegate *weakSelf = self;
    self.eventTapRetryTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *timer) {
        AppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil) {
            [timer invalidate];
            return;
        }

        if ([strongSelf installEventTap]) {
            [strongSelf removeFallbackMonitor];
            [timer invalidate];
            strongSelf.eventTapRetryTimer = nil;
        }
    }];
}

- (BOOL)installEventTap {
    if (self.eventTap != NULL) {
        return YES;
    }

    CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown);
    self.eventTap = CGEventTapCreate(kCGSessionEventTap,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionListenOnly,
                                     mask,
                                     touchBarFreeEventCallback,
                                     (__bridge void *)self);

    if (self.eventTap == NULL) {
        return NO;
    }

    self.eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), self.eventTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(self.eventTap, true);
    return YES;
}

- (void)installFallbackMonitor {
    if (self.fallbackMonitor != nil) {
        return;
    }

    __weak AppDelegate *weakSelf = self;
    self.fallbackMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskFlagsChanged | NSEventMaskKeyDown) handler:^(NSEvent *event) {
        CGEventType type = event.type == NSEventTypeFlagsChanged ? kCGEventFlagsChanged : kCGEventKeyDown;
        CGEventFlags flags = (CGEventFlags)event.modifierFlags;
        [weakSelf handleFlags:flags keyCode:(CGKeyCode)event.keyCode eventType:type isRepeat:event.isARepeat];
    }];
}

- (void)removeFallbackMonitor {
    if (self.fallbackMonitor != nil) {
        [NSEvent removeMonitor:self.fallbackMonitor];
        self.fallbackMonitor = nil;
    }
}

- (void)requestKeyboardMonitoringPermission {
    if (@available(macOS 10.15, *)) {
        if (!CGPreflightListenEventAccess()) {
            CGRequestListenEventAccess();
        }
    } else if (!AXIsProcessTrusted()) {
        NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }
}

- (void)showPreferences:(id)sender {
    if (self.preferencesWindow == nil) {
        [self buildPreferencesWindow];
    }

    [self renderPreferencesTab];
    [NSApp activateIgnoringOtherApps:YES];
    [self.preferencesWindow center];
    [self.preferencesWindow makeKeyAndOrderFront:nil];
}

- (void)buildPreferencesWindow {
    NSRect frame = NSMakeRect(0, 0, 720, 460);
    self.preferencesWindow = [[NSWindow alloc] initWithContentRect:frame
                                                         styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
    self.preferencesWindow.title = @"Touch Bar Free";
    self.preferencesWindow.titlebarAppearsTransparent = NO;

    PreferencesBackgroundView *content = [[PreferencesBackgroundView alloc] initWithFrame:frame];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.preferencesWindow.contentView = content;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(34, 360, 64, 64)];
    icon.image = [NSImage imageNamed:@"AppIcon"];
    [content addSubview:icon];

    NSTextField *title = [self labelWithString:@"General" frame:NSMakeRect(112, 382, 260, 36)];
    title.tag = 8001;
    title.font = [NSFont systemFontOfSize:25 weight:NSFontWeightBold];
    [content addSubview:title];

    self.generalTabButton = [self tabButtonWithTitle:@"General" frame:NSMakeRect(474, 378, 94, 34) action:@selector(showGeneralPreferences:)];
    [content addSubview:self.generalTabButton];

    self.hotKeysTabButton = [self tabButtonWithTitle:@"Hot Keys" frame:NSMakeRect(576, 378, 104, 34) action:@selector(showHotKeysPreferences:)];
    [content addSubview:self.hotKeysTabButton];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 344, 720, 1)];
    separator.boxType = NSBoxSeparator;
    [content addSubview:separator];

    self.preferencesContentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 720, 344)];
    [content addSubview:self.preferencesContentView];
}

- (NSButton *)tabButtonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    button.alignment = NSTextAlignmentCenter;
    return button;
}

- (void)showGeneralPreferences:(id)sender {
    self.preferencesTab = @"general";
    [self renderPreferencesTab];
}

- (void)showHotKeysPreferences:(id)sender {
    self.preferencesTab = @"hotkeys";
    [self renderPreferencesTab];
}

- (void)renderPreferencesTab {
    NSTextField *title = [self.preferencesWindow.contentView viewWithTag:8001];
    title.stringValue = [self.preferencesTab isEqualToString:@"general"] ? @"General" : @"Hot Keys";
    self.generalTabButton.state = [self.preferencesTab isEqualToString:@"general"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.hotKeysTabButton.state = [self.preferencesTab isEqualToString:@"hotkeys"] ? NSControlStateValueOn : NSControlStateValueOff;

    for (NSView *view in self.preferencesContentView.subviews.copy) {
        [view removeFromSuperview];
    }

    if ([self.preferencesTab isEqualToString:@"general"]) {
        [self renderGeneralPreferences];
    } else {
        [self renderHotKeysPreferences];
    }
}

- (void)renderGeneralPreferences {
    NSView *content = self.preferencesContentView;
    NSBox *card = [self cardWithFrame:NSMakeRect(64, 34, 592, 274)];
    [content addSubview:card];

    CGFloat labelX = 104;
    CGFloat controlX = 264;

    [content addSubview:[self rightLabelWithString:@"Login:" frame:NSMakeRect(labelX, 262, 142, 24)]];
    self.launchAtLoginCheckbox = [self checkboxWithTitle:@"Launch Touch Bar Free at login" frame:NSMakeRect(controlX, 262, 330, 24) action:@selector(launchAtLoginChanged:)];
    self.launchAtLoginCheckbox.enabled = [self supportsLaunchAtLogin];
    self.launchAtLoginCheckbox.state = [self launchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:self.launchAtLoginCheckbox];

    [content addSubview:[self rightLabelWithString:@"Updates:" frame:NSMakeRect(labelX, 222, 142, 24)]];
    self.updatesCheckbox = [self checkboxWithTitle:@"Automatically check for updates" frame:NSMakeRect(controlX, 222, 330, 24) action:@selector(updatesChanged:)];
    self.updatesCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:kUpdatesDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:self.updatesCheckbox];

    [content addSubview:[self rightLabelWithString:@"Quick Actions:" frame:NSMakeRect(labelX, 182, 142, 24)]];
    self.quickActionsCheckbox = [self checkboxWithTitle:@"Display essential controls in the menu" frame:NSMakeRect(controlX, 182, 360, 24) action:@selector(quickActionsChanged:)];
    self.quickActionsCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:kQuickActionsDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:self.quickActionsCheckbox];

    [content addSubview:[self rightLabelWithString:@"Status Icon:" frame:NSMakeRect(labelX, 134, 142, 24)]];
    [self addRadioGroupToView:content
                      options:[self iconThemeOptions]
                  selectedKey:[[NSUserDefaults standardUserDefaults] stringForKey:kIconThemeDefaultsKey]
                         frame:NSMakeRect(controlX, 125, 390, 36)
                        action:@selector(iconThemeRadioChanged:)];

    [content addSubview:[self rightLabelWithString:@"Escape:" frame:NSMakeRect(labelX, 78, 142, 24)]];
    self.noPhysicalEscapeCheckbox = [self checkboxWithTitle:@"I don't have a physical 'esc' key" frame:NSMakeRect(controlX, 78, 330, 24) action:@selector(escapeOptionsChanged:)];
    self.noPhysicalEscapeCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:kNoPhysicalEscapeDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:self.noPhysicalEscapeCheckbox];

    self.showEscapeWhenHiddenCheckbox = [self checkboxWithTitle:@"Display the 'esc' key when Touch Bar is hidden" frame:NSMakeRect(controlX, 42, 380, 24) action:@selector(escapeOptionsChanged:)];
    self.showEscapeWhenHiddenCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:kShowEscapeWhenHiddenDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.showEscapeWhenHiddenCheckbox.enabled = self.noPhysicalEscapeCheckbox.state == NSControlStateValueOn;
    [content addSubview:self.showEscapeWhenHiddenCheckbox];
}

- (void)renderHotKeysPreferences {
    NSView *content = self.preferencesContentView;

    NSBox *card = [self cardWithFrame:NSMakeRect(54, 28, 612, 292)];
    [content addSubview:card];

    NSTextField *heading = [self labelWithString:@"Hide / Show" frame:NSMakeRect(86, 272, 160, 24)];
    heading.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    [content addSubview:heading];

    [content addSubview:[self rightLabelWithString:@"Default Touch Bar:" frame:NSMakeRect(76, 224, 170, 24)]];
    [self addRadioGroupToView:content
                      options:[self primaryShortcutOptions]
                  selectedKey:self.selectedKey
                         frame:NSMakeRect(264, 211, 360, 58)
                        action:@selector(shortcutRadioChanged:)];

    NSButton *defaultEnabled = [self checkboxWithTitle:@"Double tap enabled" frame:NSMakeRect(264, 176, 190, 24) action:nil];
    defaultEnabled.state = NSControlStateValueOn;
    defaultEnabled.enabled = NO;
    [content addSubview:defaultEnabled];

    [content addSubview:[self rightLabelWithString:@"Fn Keys:" frame:NSMakeRect(76, 124, 170, 24)]];
    self.functionKeysCheckbox = [self checkboxWithTitle:@"Enable a second double-tap key" frame:NSMakeRect(264, 124, 260, 24) action:@selector(functionKeysChanged:)];
    self.functionKeysCheckbox.state = [[NSUserDefaults standardUserDefaults] boolForKey:kFunctionKeysEnabledDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:self.functionKeysCheckbox];

    NSView *functionOptions = [[NSView alloc] initWithFrame:NSMakeRect(264, 72, 360, 44)];
    functionOptions.tag = 8100;
    functionOptions.alphaValue = self.functionKeysCheckbox.state == NSControlStateValueOn ? 1.0 : 0.42;
    [self addRadioGroupToView:functionOptions
                      options:[self functionShortcutOptions]
                  selectedKey:self.functionKey
                         frame:NSMakeRect(0, 0, 360, 44)
                        action:@selector(functionShortcutRadioChanged:)];
    [content addSubview:functionOptions];

    NSButton *help = [NSButton buttonWithTitle:@"Touch Bar not hiding? Open Input Monitoring" target:self action:@selector(openInputMonitoringSettings:)];
    help.frame = NSMakeRect(86, 30, 290, 30);
    help.bezelStyle = NSBezelStyleRounded;
    [content addSubview:help];

    NSTextField *hint = [self labelWithString:@"For F1-F12, set Keyboard settings so the Touch Bar shows App Controls or Expanded Control Strip." frame:NSMakeRect(392, 29, 230, 34)];
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    hint.maximumNumberOfLines = 2;
    [content addSubview:hint];
}

- (NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = string;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [NSFont systemFontOfSize:13];
    return label;
}

- (NSTextField *)rightLabelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [self labelWithString:string frame:frame];
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont systemFontOfSize:16 weight:NSFontWeightRegular];
    return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:frame];
    checkbox.buttonType = NSButtonTypeSwitch;
    checkbox.title = title;
    checkbox.font = [NSFont systemFontOfSize:16];
    checkbox.target = self;
    checkbox.action = action;
    return checkbox;
}

- (NSBox *)cardWithFrame:(NSRect)frame {
    NSBox *box = [[NSBox alloc] initWithFrame:frame];
    box.boxType = NSBoxCustom;
    box.borderType = NSLineBorder;
    box.cornerRadius = 14;
    box.borderColor = [NSColor colorWithCalibratedWhite:0 alpha:0.06];
    box.fillColor = [NSColor colorWithCalibratedWhite:1 alpha:0.72];
    return box;
}

- (void)addRadioGroupToView:(NSView *)view options:(NSArray<NSDictionary *> *)options selectedKey:(NSString *)selectedKey frame:(NSRect)frame action:(SEL)action {
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y + frame.size.height - 24;
    CGFloat startX = x;
    CGFloat maxX = frame.origin.x + frame.size.width;

    for (NSDictionary *option in options) {
        NSString *title = option[@"title"];
        CGFloat width = MAX(76, MIN(132, title.length * 9 + 38));
        if (x + width > maxX) {
            x = startX;
            y -= 28;
        }

        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, width, 24)];
        button.buttonType = NSButtonTypeRadio;
        button.title = title;
        button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        button.target = self;
        button.action = action;
        button.representedObject = option[@"key"];
        button.state = [option[@"key"] isEqualToString:selectedKey] ? NSControlStateValueOn : NSControlStateValueOff;
        [view addSubview:button];
        x += width + 8;
    }
}

- (NSArray<NSDictionary *> *)shortcutOptions {
    return @[
        @{ @"title": @"Command", @"key": @"command" },
        @{ @"title": @"Control", @"key": @"control" },
        @{ @"title": @"Option", @"key": @"option" },
        @{ @"title": @"Shift", @"key": @"shift" },
        @{ @"title": @"Fn / Globe", @"key": @"fn" },
        @{ @"title": @"Escape", @"key": @"escape" },
        @{ @"title": @"F1", @"key": @"f1" },
        @{ @"title": @"F2", @"key": @"f2" },
        @{ @"title": @"F3", @"key": @"f3" },
        @{ @"title": @"F4", @"key": @"f4" },
        @{ @"title": @"F5", @"key": @"f5" },
        @{ @"title": @"F6", @"key": @"f6" },
        @{ @"title": @"F7", @"key": @"f7" },
        @{ @"title": @"F8", @"key": @"f8" },
        @{ @"title": @"F9", @"key": @"f9" },
        @{ @"title": @"F10", @"key": @"f10" },
        @{ @"title": @"F11", @"key": @"f11" },
        @{ @"title": @"F12", @"key": @"f12" }
    ];
}

- (NSArray<NSDictionary *> *)primaryShortcutOptions {
    return @[
        @{ @"title": @"Command", @"key": @"command" },
        @{ @"title": @"Control", @"key": @"control" },
        @{ @"title": @"Option", @"key": @"option" },
        @{ @"title": @"Shift", @"key": @"shift" },
        @{ @"title": @"Fn", @"key": @"fn" },
        @{ @"title": @"Escape", @"key": @"escape" }
    ];
}

- (NSArray<NSDictionary *> *)functionShortcutOptions {
    return @[
        @{ @"title": @"Option", @"key": @"option" },
        @{ @"title": @"Control", @"key": @"control" },
        @{ @"title": @"F1", @"key": @"f1" },
        @{ @"title": @"F2", @"key": @"f2" },
        @{ @"title": @"F3", @"key": @"f3" },
        @{ @"title": @"F4", @"key": @"f4" },
        @{ @"title": @"F5", @"key": @"f5" },
        @{ @"title": @"F6", @"key": @"f6" },
        @{ @"title": @"F7", @"key": @"f7" },
        @{ @"title": @"F8", @"key": @"f8" },
        @{ @"title": @"F9", @"key": @"f9" },
        @{ @"title": @"F10", @"key": @"f10" },
        @{ @"title": @"F11", @"key": @"f11" },
        @{ @"title": @"F12", @"key": @"f12" }
    ];
}

- (NSArray<NSDictionary *> *)iconThemeOptions {
    return @[
        @{ @"title": @"Touch Bar", @"key": @"touchbar" },
        @{ @"title": @"Eye", @"key": @"eye" },
        @{ @"title": @"Text TB", @"key": @"text" },
        @{ @"title": @"Auto Hidden / Visible", @"key": @"auto" }
    ];
}

- (void)shortcutSelectionChanged:(id)sender {
    NSString *key = self.shortcutPopup.selectedItem.representedObject ?: kDefaultSelectedKey;
    self.selectedKey = key;
    self.selectedKeyWasDown = NO;
    self.lastTapTime = 0;
    [[NSUserDefaults standardUserDefaults] setObject:key forKey:kSelectedKeyDefaultsKey];
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"Touch Bar Free - double-tap %@ to toggle", [self displayNameForKey:key]];
}

- (void)functionShortcutSelectionChanged:(id)sender {
    NSString *key = self.functionShortcutPopup.selectedItem.representedObject ?: kDefaultFunctionKey;
    self.functionKey = key;
    self.functionKeyWasDown = NO;
    self.lastFunctionTapTime = 0;
    [[NSUserDefaults standardUserDefaults] setObject:key forKey:kFunctionKeyDefaultsKey];
}

- (void)functionKeysChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(self.functionKeysCheckbox.state == NSControlStateValueOn) forKey:kFunctionKeysEnabledDefaultsKey];
    self.functionShortcutPopup.enabled = self.functionKeysCheckbox.state == NSControlStateValueOn;
}

- (void)launchAtLoginChanged:(id)sender {
    BOOL enabled = self.launchAtLoginCheckbox.state == NSControlStateValueOn;
    [self setLaunchAtLoginEnabled:enabled];
    self.launchAtLoginCheckbox.state = [self launchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)quickActionsChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(self.quickActionsCheckbox.state == NSControlStateValueOn) forKey:kQuickActionsDefaultsKey];
    [self rebuildStatusMenu];
}

- (void)updatesChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(self.updatesCheckbox.state == NSControlStateValueOn) forKey:kUpdatesDefaultsKey];
    if (self.updatesCheckbox.state == NSControlStateValueOn) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Updates are local in this free build.";
        alert.informativeText = @"Sparkle-style automatic updates need a signed update feed. This build keeps the setting for future releases, but it will not contact an update server.";
        [alert runModal];
    }
}

- (void)iconThemeChanged:(id)sender {
    NSString *theme = self.statusIconThemePopup.selectedItem.representedObject ?: @"touchbar";
    [[NSUserDefaults standardUserDefaults] setObject:theme forKey:kIconThemeDefaultsKey];
    self.statusItem.button.image = [self statusIconImage];
}

- (void)escapeOptionsChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(self.noPhysicalEscapeCheckbox.state == NSControlStateValueOn) forKey:kNoPhysicalEscapeDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setBool:(self.showEscapeWhenHiddenCheckbox.state == NSControlStateValueOn) forKey:kShowEscapeWhenHiddenDefaultsKey];
    self.showEscapeWhenHiddenCheckbox.enabled = self.noPhysicalEscapeCheckbox.state == NSControlStateValueOn;
}

- (BOOL)supportsLaunchAtLogin {
    if (@available(macOS 13.0, *)) {
        return YES;
    }
    return NO;
}

- (BOOL)launchAtLoginEnabled {
    if (@available(macOS 13.0, *)) {
        return [[SMAppService mainAppService] status] == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (void)setLaunchAtLoginEnabled:(BOOL)enabled {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        BOOL success = enabled ? [[SMAppService mainAppService] registerAndReturnError:&error] : [[SMAppService mainAppService] unregisterAndReturnError:&error];
        if (!success && error != nil) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Launch at login could not be changed.";
            alert.informativeText = error.localizedDescription;
            [alert runModal];
        }
    }
}

- (void)openInputMonitoringSettings:(id)sender {
    [self requestKeyboardMonitoringPermission];

    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)handleFlags:(CGEventFlags)flags keyCode:(CGKeyCode)keyCode eventType:(CGEventType)type isRepeat:(BOOL)isRepeat {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleShortcutKey:self.selectedKey
                          flags:flags
                        keyCode:keyCode
                      eventType:type
                       isRepeat:isRepeat
                      wasDown:&_selectedKeyWasDown
                    lastTapTime:&_lastTapTime];

        if ([[NSUserDefaults standardUserDefaults] boolForKey:kFunctionKeysEnabledDefaultsKey]) {
            [self handleShortcutKey:self.functionKey
                              flags:flags
                            keyCode:keyCode
                          eventType:type
                           isRepeat:isRepeat
                          wasDown:&_functionKeyWasDown
                        lastTapTime:&_lastFunctionTapTime];
        }
    });
}

- (void)handleShortcutKey:(NSString *)key flags:(CGEventFlags)flags keyCode:(CGKeyCode)keyCode eventType:(CGEventType)type isRepeat:(BOOL)isRepeat wasDown:(BOOL *)wasDown lastTapTime:(NSTimeInterval *)lastTapTime {
    if ([self isModifierKey:key]) {
            if (type != kCGEventFlagsChanged) {
                return;
            }

            BOOL keyDown = [self modifierKey:key isDownInFlags:flags];
            if (!keyDown) {
                *wasDown = NO;
                return;
            }

            if (*wasDown || [self otherModifiersAreDownInFlags:flags selectedKey:key]) {
                return;
            }

            *wasDown = YES;
            [self registerShortcutTap:lastTapTime];
            return;
        }

        if (type == kCGEventKeyDown && !isRepeat && keyCode == [self keyCodeForKey:key]) {
            [self registerShortcutTap:lastTapTime];
        }
}

- (void)registerShortcutTap:(NSTimeInterval *)lastTapTime {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (*lastTapTime > 0 && now - *lastTapTime <= kDoubleTapInterval) {
        *lastTapTime = 0;
        [self toggleBlankTouchBar:nil];
    } else {
        *lastTapTime = now;
    }
}

- (BOOL)isModifierKey:(NSString *)key {
    return [@[@"command", @"control", @"option", @"shift", @"fn"] containsObject:key];
}

- (BOOL)modifierKey:(NSString *)key isDownInFlags:(CGEventFlags)flags {
    if ([key isEqualToString:@"command"]) {
        return (flags & kCGEventFlagMaskCommand) != 0;
    }
    if ([key isEqualToString:@"control"]) {
        return (flags & kCGEventFlagMaskControl) != 0;
    }
    if ([key isEqualToString:@"option"]) {
        return (flags & kCGEventFlagMaskAlternate) != 0;
    }
    if ([key isEqualToString:@"shift"]) {
        return (flags & kCGEventFlagMaskShift) != 0;
    }
    if ([key isEqualToString:@"fn"]) {
        return (flags & kCGEventFlagMaskSecondaryFn) != 0;
    }
    return NO;
}

- (BOOL)otherModifiersAreDownInFlags:(CGEventFlags)flags selectedKey:(NSString *)key {
    CGEventFlags selectedFlag = 0;

    if ([key isEqualToString:@"command"]) {
        selectedFlag = kCGEventFlagMaskCommand;
    } else if ([key isEqualToString:@"control"]) {
        selectedFlag = kCGEventFlagMaskControl;
    } else if ([key isEqualToString:@"option"]) {
        selectedFlag = kCGEventFlagMaskAlternate;
    } else if ([key isEqualToString:@"shift"]) {
        selectedFlag = kCGEventFlagMaskShift;
    } else if ([key isEqualToString:@"fn"]) {
        selectedFlag = kCGEventFlagMaskSecondaryFn;
    }

    CGEventFlags otherFlags = kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskShift | kCGEventFlagMaskSecondaryFn;
    return (flags & (otherFlags & ~selectedFlag)) != 0;
}

- (CGKeyCode)keyCodeForKey:(NSString *)key {
    NSDictionary<NSString *, NSNumber *> *keyCodes = @{
        @"escape": @53,
        @"f1": @122,
        @"f2": @120,
        @"f3": @99,
        @"f4": @118,
        @"f5": @96,
        @"f6": @97,
        @"f7": @98,
        @"f8": @100,
        @"f9": @101,
        @"f10": @109,
        @"f11": @103,
        @"f12": @111
    };
    return (CGKeyCode)[keyCodes[key] unsignedShortValue];
}

- (NSString *)displayNameForKey:(NSString *)key {
    for (NSDictionary *option in [self shortcutOptions]) {
        if ([option[@"key"] isEqualToString:key]) {
            return option[@"title"];
        }
    }
    return @"Command";
}

- (NSString *)displayNameForIconTheme:(NSString *)theme {
    for (NSDictionary *option in [self iconThemeOptions]) {
        if ([option[@"key"] isEqualToString:theme]) {
            return option[@"title"];
        }
    }
    return @"Touch Bar";
}

- (NSImage *)statusIconImage {
    NSString *theme = [[NSUserDefaults standardUserDefaults] stringForKey:kIconThemeDefaultsKey] ?: @"touchbar";
    if ([theme isEqualToString:@"auto"]) {
        theme = self.blankTouchBarShown ? @"eye" : @"touchbar";
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(22, 18)];
    [image lockFocus];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 22, 18));

    [[NSColor labelColor] setStroke];
    [[NSColor labelColor] setFill];

    if ([theme isEqualToString:@"text"]) {
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: NSColor.labelColor
        };
        [@"TB" drawInRect:NSMakeRect(2, 1, 20, 16) withAttributes:attributes];
    } else if ([theme isEqualToString:@"eye"]) {
        NSBezierPath *eye = [NSBezierPath bezierPath];
        [eye moveToPoint:NSMakePoint(2, 9)];
        [eye curveToPoint:NSMakePoint(20, 9) controlPoint1:NSMakePoint(7, 16) controlPoint2:NSMakePoint(15, 16)];
        [eye curveToPoint:NSMakePoint(2, 9) controlPoint1:NSMakePoint(15, 2) controlPoint2:NSMakePoint(7, 2)];
        eye.lineWidth = 1.8;
        [eye stroke];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(8, 5, 6, 6)] fill];
        NSBezierPath *slash = [NSBezierPath bezierPath];
        [slash moveToPoint:NSMakePoint(4, 2)];
        [slash lineToPoint:NSMakePoint(18, 16)];
        slash.lineWidth = 2;
        [slash stroke];
    } else {
        NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 4, 18, 10) xRadius:3 yRadius:3];
        bar.lineWidth = 1.8;
        [bar stroke];
        NSBezierPath *notch = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(8, 6, 6, 6) xRadius:1.5 yRadius:1.5];
        [notch fill];
    }

    [image unlockFocus];
    image.template = YES;
    return image;
}

- (void)updateVisibleState {
    self.toggleItem.title = self.blankTouchBarShown ? @"Show Touch Bar" : @"Hide Touch Bar";
    self.toggleItem.state = self.blankTouchBarShown ? NSControlStateValueOn : NSControlStateValueOff;
    self.statusItem.button.image = [self statusIconImage];
}

- (NSMenuItem *)systemKeyMenuItemWithTitle:(NSString *)title keyType:(int)keyType {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(sendSystemKeyFromMenu:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = @(keyType);
    return item;
}

- (void)sendSystemKeyFromMenu:(NSMenuItem *)sender {
    [self sendSystemKey:[sender.representedObject intValue]];
}

- (void)sendEscapeKey:(id)sender {
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, 53, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, 53, false);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
}

- (void)sendSystemKey:(int)keyType {
    [self postSystemKey:keyType down:YES];
    [self postSystemKey:keyType down:NO];
}

- (void)postSystemKey:(int)keyType down:(BOOL)down {
    int keyState = down ? NX_KEYDOWN : NX_KEYUP;
    int flags = keyState << 8;
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                        location:NSZeroPoint
                                   modifierFlags:flags
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:8
                                           data1:(keyType << 16) | flags
                                           data2:-1];
    if (event.CGEvent != NULL) {
        CGEventPost(kCGHIDEventTap, event.CGEvent);
    }
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if ([identifier isEqualToString:kEscapeItemIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        NSButton *button = [NSButton buttonWithTitle:@"esc" target:self action:@selector(sendEscapeKey:)];
        button.bezelStyle = NSBezelStyleTexturedRounded;
        item.view = button;
        item.visibilityPriority = NSTouchBarItemPriorityHigh;
        return item;
    }

    if (![identifier isEqualToString:kBlankItemIdentifier]) {
        return nil;
    }

    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    BlankTouchBarView *blankView = [[BlankTouchBarView alloc] initWithFrame:NSMakeRect(0, 0, 2400, 30)];
    blankView.wantsLayer = YES;
    blankView.layer.backgroundColor = NSColor.blackColor.CGColor;
    blankView.translatesAutoresizingMaskIntoConstraints = NO;
    [[blankView.widthAnchor constraintGreaterThanOrEqualToConstant:2400] setActive:YES];
    [[blankView.heightAnchor constraintEqualToConstant:30] setActive:YES];
    item.view = blankView;
    item.visibilityPriority = NSTouchBarItemPriorityHigh;
    return item;
}

- (void)toggleBlankTouchBar:(id)sender {
    if (self.blankTouchBarShown) {
        [self dismissBlankTouchBar:sender];
    } else {
        [self showBlankTouchBar:sender];
    }
}

- (void)showBlankTouchBar:(id)sender {
    DFRSystemModalShowsCloseBoxWhenFrontMost(NO);

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kNoPhysicalEscapeDefaultsKey] &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kShowEscapeWhenHiddenDefaultsKey]) {
        self.blankTouchBar.defaultItemIdentifiers = @[ kEscapeItemIdentifier, kBlankItemIdentifier ];
    } else {
        self.blankTouchBar.defaultItemIdentifiers = @[ kBlankItemIdentifier ];
    }

    SEL newPlacementSelector = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    SEL oldPlacementSelector = NSSelectorFromString(@"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:");
    SEL newSelector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    SEL oldSelector = NSSelectorFromString(@"presentSystemModalFunctionBar:systemTrayItemIdentifier:");

    if ([NSTouchBar respondsToSelector:newPlacementSelector]) {
        typedef void (*PresentPlacementImp)(id, SEL, NSTouchBar *, long long, NSTouchBarItemIdentifier);
        PresentPlacementImp imp = (PresentPlacementImp)[NSTouchBar methodForSelector:newPlacementSelector];
        imp(NSTouchBar.class, newPlacementSelector, self.blankTouchBar, 1, kTrayIdentifier);
    } else if ([NSTouchBar respondsToSelector:oldPlacementSelector]) {
        typedef void (*PresentPlacementImp)(id, SEL, NSTouchBar *, long long, NSTouchBarItemIdentifier);
        PresentPlacementImp imp = (PresentPlacementImp)[NSTouchBar methodForSelector:oldPlacementSelector];
        imp(NSTouchBar.class, oldPlacementSelector, self.blankTouchBar, 1, kTrayIdentifier);
    } else if ([NSTouchBar respondsToSelector:newSelector]) {
        typedef void (*PresentImp)(id, SEL, NSTouchBar *, NSTouchBarItemIdentifier);
        PresentImp imp = (PresentImp)[NSTouchBar methodForSelector:newSelector];
        imp(NSTouchBar.class, newSelector, self.blankTouchBar, kTrayIdentifier);
    } else if ([NSTouchBar respondsToSelector:oldSelector]) {
        typedef void (*PresentImp)(id, SEL, NSTouchBar *, NSTouchBarItemIdentifier);
        PresentImp imp = (PresentImp)[NSTouchBar methodForSelector:oldSelector];
        imp(NSTouchBar.class, oldSelector, self.blankTouchBar, kTrayIdentifier);
    }

    self.blankTouchBarShown = YES;
    [self updateVisibleState];
}

- (void)dismissBlankTouchBar:(id)sender {
    SEL newSelector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    SEL oldSelector = NSSelectorFromString(@"dismissSystemModalFunctionBar:");

    if ([NSTouchBar respondsToSelector:newSelector]) {
        typedef void (*DismissImp)(id, SEL, NSTouchBar *);
        DismissImp imp = (DismissImp)[NSTouchBar methodForSelector:newSelector];
        imp(NSTouchBar.class, newSelector, self.blankTouchBar);
    } else if ([NSTouchBar respondsToSelector:oldSelector]) {
        typedef void (*DismissImp)(id, SEL, NSTouchBar *);
        DismissImp imp = (DismissImp)[NSTouchBar methodForSelector:oldSelector];
        imp(NSTouchBar.class, oldSelector, self.blankTouchBar);
    }

    self.blankTouchBarShown = NO;
    [self updateVisibleState];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
