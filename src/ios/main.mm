#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>

#include "liberty/content_provider.hpp"

#include <exception>
#include <filesystem>
#include <string>

#ifndef LIBERTY_BUILD_COMMIT
#define LIBERTY_BUILD_COMMIT "unknown"
#endif
#ifndef LIBERTY_UPSTREAM_COMMIT
#define LIBERTY_UPSTREAM_COMMIT "unknown"
#endif
#ifndef LIBERTY_IOS_CONTENT_MODE
#define LIBERTY_IOS_CONTENT_MODE "imported"
#endif
#ifndef LIBERTY_IOS_ALLOW_UNPINNED_CONTENT
#define LIBERTY_IOS_ALLOW_UNPINNED_CONTENT 0
#endif

static NSURL *LibertyApplicationSupportURL(void) {
    NSURL *root = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [root URLByAppendingPathComponent:@"LibertyRecomp" isDirectory:YES];
}

static NSURL *LibertyDocumentsURL(void) {
    return [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

static BOOL LibertyExcludeFromBackup(NSURL *url, NSError **error) {
    NSNumber *yes = @YES;
    return [url setResourceValue:yes forKey:NSURLIsExcludedFromBackupKey error:error];
}

static NSString *LibertySHA256(NSURL *fileURL, NSError **error) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:fileURL error:error];
    if (!handle) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    @try {
        while (true) {
            NSData *chunk = [handle readDataOfLength:1024 * 1024];
            if (chunk.length == 0) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"LibertyContent" code:20 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to hash executable"}];
        [handle closeFile];
        return nil;
    }
    [handle closeFile];
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(bytes, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) [hex appendFormat:@"%02x", bytes[index]];
    return hex;
}

static unsigned long long LibertyDirectorySize(NSURL *rootURL) {
    NSArray<NSURLResourceKey> *keys = @[NSURLIsRegularFileKey, NSURLFileSizeKey];
    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:rootURL includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url, NSError *error) {
        NSLog(@"[Liberty] size scan skipped %@: %@", url.path, error);
        return YES;
    }];
    unsigned long long total = 0;
    for (NSURL *url in enumerator) {
        NSNumber *isRegular = nil;
        NSNumber *size = nil;
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (isRegular.boolValue) {
            [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            total += size.unsignedLongLongValue;
        }
    }
    return total;
}

static NSDictionary *LibertyCompatibilityManifest(NSError **error) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"gta4_x360_supported" withExtension:@"json"];
    if (!url) {
        if (error) *error = [NSError errorWithDomain:@"LibertyContent" code:21 userInfo:@{NSLocalizedDescriptionKey: @"Compatibility manifest is missing from the app bundle."}];
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"LibertyContent" code:22 userInfo:@{NSLocalizedDescriptionKey: @"Compatibility manifest is not a JSON object."}];
        return nil;
    }
    return (NSDictionary *)object;
}

static NSArray<NSString *> *LibertyRequiredFiles(NSDictionary *manifest) {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (id entry in manifest[@"requiredFiles"]) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            id path = ((NSDictionary *)entry)[@"path"];
            if ([path isKindOfClass:[NSString class]]) [files addObject:path];
        }
    }
    return files;
}

static NSDictionary *LibertyMatchedRevision(NSDictionary *manifest, NSString *sha256) {
    for (id entry in manifest[@"supportedRevisions"]) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *expected = ((NSDictionary *)entry)[@"xexSha256"];
        if ([expected isKindOfClass:[NSString class]] && [expected caseInsensitiveCompare:sha256] == NSOrderedSame) return (NSDictionary *)entry;
    }
    return nil;
}

@interface LibertyShellViewController : UIViewController <MTKViewDelegate, UIDocumentPickerDelegate>
@end

@implementation LibertyShellViewController {
    MTKView *_metalView;
    id<MTLCommandQueue> _commandQueue;
    UILabel *_statusLabel;
    UILabel *_diagnosticsLabel;
    UIButton *_importButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _commandQueue = [device newCommandQueue];
    _metalView = [[MTKView alloc] initWithFrame:CGRectZero device:device];
    _metalView.translatesAutoresizingMaskIntoConstraints = NO;
    _metalView.delegate = self;
    _metalView.paused = NO;
    _metalView.enableSetNeedsDisplay = NO;
    _metalView.preferredFramesPerSecond = 30;
    _metalView.clearColor = MTLClearColorMake(0.035, 0.045, 0.055, 1.0);
    [self.view addSubview:_metalView];

    UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.layer.cornerRadius = 20.0;
    panel.clipsToBounds = YES;
    [self.view addSubview:panel];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Liberty Recompiled";
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"Native ARM64 / Metal foundation";
    subtitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    subtitle.textColor = UIColor.secondaryLabelColor;
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.numberOfLines = 0;
    _statusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _statusLabel.textColor = UIColor.whiteColor;
    _diagnosticsLabel = [[UILabel alloc] init];
    _diagnosticsLabel.numberOfLines = 0;
    _diagnosticsLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _diagnosticsLabel.textColor = UIColor.secondaryLabelColor;
    _importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_importButton setTitle:@"Import Owned GTA IV Folder" forState:UIControlStateNormal];
    _importButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _importButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [_importButton addTarget:self action:@selector(importPressed) forControlEvents:UIControlEventTouchUpInside];
    UILabel *legal = [[UILabel alloc] init];
    legal.numberOfLines = 0;
    legal.text = @"No Rockstar game data is included. Import files only from a legally owned Xbox 360 copy.";
    legal.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    legal.textColor = UIColor.tertiaryLabelColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle, _statusLabel, _diagnosticsLabel, _importButton, legal]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    [panel.contentView addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_metalView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_metalView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_metalView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_metalView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [panel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [panel.widthAnchor constraintLessThanOrEqualToConstant:540],
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-22],
        [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor constant:-20]
    ]];

    [self configureAudioSession];
    [self prepareContentDirectories];
    [self refreshDiagnostics];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(environmentChanged) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(environmentChanged) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(environmentChanged) name:GCControllerDidDisconnectNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)configureAudioSession {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryAmbient mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:&error]) NSLog(@"[Liberty] AVAudioSession category failed: %@", error);
    error = nil;
    if (![session setActive:YES error:&error]) NSLog(@"[Liberty] AVAudioSession activation failed: %@", error);
}

- (void)prepareContentDirectories {
    NSURL *appSupport = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *documents = LibertyDocumentsURL();
    try {
        liberty::content::ImportedContentProvider provider(std::filesystem::path(appSupport.path.UTF8String), std::filesystem::path(documents.path.UTF8String));
        provider.ensure_layout();
        auto layout = provider.layout();
        NSArray<NSString *> *excluded = @[[NSString stringWithUTF8String:layout.dlc_root.string().c_str()], [NSString stringWithUTF8String:layout.cache_root.string().c_str()]];
        for (NSString *path in excluded) {
            NSError *error = nil;
            LibertyExcludeFromBackup([NSURL fileURLWithPath:path isDirectory:YES], &error);
            if (error) NSLog(@"[Liberty] backup exclusion failed for %@: %@", path, error);
        }
    } catch (const std::exception& exception) {
        NSLog(@"[Liberty] content directory setup failed: %s", exception.what());
    }
    [self refreshContentStatus];
}

- (void)refreshContentStatus {
    NSURL *appSupport = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *documents = LibertyDocumentsURL();
    try {
        liberty::content::ImportedContentProvider provider(std::filesystem::path(appSupport.path.UTF8String), std::filesystem::path(documents.path.UTF8String));
        _statusLabel.text = provider.validate_required_files().ok ? @"Game content: imported and structurally valid" : @"Game content: not installed";
    } catch (...) {
        _statusLabel.text = @"Game content: unavailable";
    }
}

- (NSString *)thermalStateText {
    switch (NSProcessInfo.processInfo.thermalState) {
        case NSProcessInfoThermalStateNominal: return @"nominal";
        case NSProcessInfoThermalStateFair: return @"fair";
        case NSProcessInfoThermalStateSerious: return @"serious";
        case NSProcessInfoThermalStateCritical: return @"critical";
    }
    return @"unknown";
}

- (void)refreshDiagnostics {
    NSString *gpuName = _metalView.device.name ?: @"No Metal device";
    _diagnosticsLabel.text = [NSString stringWithFormat:@"app: %s\nupstream: %.12s\niOS: %@\ndevice: %@\nGPU: %@\nCPU cores: %lu\nthermal: %@\ncontrollers: %lu\ncontent mode: %s", LIBERTY_BUILD_COMMIT, LIBERTY_UPSTREAM_COMMIT, UIDevice.currentDevice.systemVersion, UIDevice.currentDevice.model, gpuName, (unsigned long)NSProcessInfo.processInfo.activeProcessorCount, [self thermalStateText], (unsigned long)GCController.controllers.count, LIBERTY_IOS_CONTENT_MODE];
}

- (void)environmentChanged { dispatch_async(dispatch_get_main_queue(), ^{ [self refreshDiagnostics]; }); }
- (void)appDidBecomeActive { _metalView.paused = NO; [self configureAudioSession]; [self refreshDiagnostics]; }
- (void)appWillResignActive { _metalView.paused = YES; [AVAudioSession.sharedInstance setActive:NO error:nil]; }

- (void)importPressed {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (BOOL)validateFolder:(NSURL *)source manifest:(NSDictionary *)manifest error:(NSError **)error sha256:(NSString **)shaOut matchedRevision:(NSDictionary **)revisionOut {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *relative in LibertyRequiredFiles(manifest)) {
        NSURL *candidate = [source URLByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:candidate.path isDirectory:&isDirectory] || isDirectory) {
            if (error) *error = [NSError errorWithDomain:@"LibertyContent" code:30 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Missing required file: %@", relative]}];
            return NO;
        }
    }
    NSString *sha = LibertySHA256([source URLByAppendingPathComponent:@"default.xex"], error);
    if (!sha) return NO;
    NSDictionary *revision = LibertyMatchedRevision(manifest, sha);
    if (!revision && !LIBERTY_IOS_ALLOW_UNPINNED_CONTENT) {
        NSString *reason = [manifest[@"supportedRevisions"] count] == 0 ? @"No supported GTA IV executable fingerprint has been configured yet." : @"This default.xex revision is not supported by the current static recompilation build.";
        if (error) *error = [NSError errorWithDomain:@"LibertyContent" code:31 userInfo:@{NSLocalizedDescriptionKey:reason, NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"SHA-256: %@", sha]}];
        if (shaOut) *shaOut = sha;
        return NO;
    }
    if (shaOut) *shaOut = sha;
    if (revisionOut) *revisionOut = revision;
    return YES;
}

- (BOOL)copyFolderAtomically:(NSURL *)source error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = LibertyApplicationSupportURL();
    NSURL *staging = [base URLByAppendingPathComponent:@"Game.staging" isDirectory:YES];
    NSURL *game = [base URLByAppendingPathComponent:@"Game" isDirectory:YES];
    NSURL *previous = [base URLByAppendingPathComponent:@"Game.previous" isDirectory:YES];
    [fm createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;
    [fm removeItemAtURL:staging error:nil];
    [fm removeItemAtURL:previous error:nil];
    if (![fm createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSArray<NSURL *> *items = [fm contentsOfDirectoryAtURL:source includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
    if (!items) { [fm removeItemAtURL:staging error:nil]; return NO; }
    for (NSURL *item in items) {
        NSURL *destination = [staging URLByAppendingPathComponent:item.lastPathComponent];
        if (![fm copyItemAtURL:item toURL:destination error:error]) { [fm removeItemAtURL:staging error:nil]; return NO; }
    }
    BOOL hadExisting = [fm fileExistsAtPath:game.path];
    if (hadExisting && ![fm moveItemAtURL:game toURL:previous error:error]) { [fm removeItemAtURL:staging error:nil]; return NO; }
    if (![fm moveItemAtURL:staging toURL:game error:error]) {
        if (hadExisting) [fm moveItemAtURL:previous toURL:game error:nil];
        return NO;
    }
    [fm removeItemAtURL:previous error:nil];
    NSError *backupError = nil;
    LibertyExcludeFromBackup(game, &backupError);
    if (backupError) NSLog(@"[Liberty] could not exclude Game from backup: %@", backupError);
    return YES;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source) return;
    _importButton.enabled = NO;
    _statusLabel.text = @"Checking selected GTA IV folder…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [source startAccessingSecurityScopedResource];
        NSError *error = nil;
        NSDictionary *manifest = LibertyCompatibilityManifest(&error);
        NSString *sha = nil;
        NSDictionary *revision = nil;
        BOOL valid = manifest != nil && [self validateFolder:source manifest:manifest error:&error sha256:&sha matchedRevision:&revision];
        if (valid) {
            unsigned long long sourceBytes = LibertyDirectorySize(source);
            NSURL *base = LibertyApplicationSupportURL();
            [NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:&error];
            NSNumber *available = nil;
            if (!error) [base getResourceValue:&available forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:&error];
            const unsigned long long reserve = 256ull * 1024ull * 1024ull;
            if (!error && available && available.unsignedLongLongValue < sourceBytes + reserve) {
                error = [NSError errorWithDomain:@"LibertyContent" code:32 userInfo:@{NSLocalizedDescriptionKey:@"Not enough free space to import the selected game folder safely."}];
                valid = NO;
            }
        }
        if (valid) {
            dispatch_async(dispatch_get_main_queue(), ^{ self->_statusLabel.text = @"Importing game data…"; });
            valid = [self copyFolderAtomically:source error:&error];
        }
        if (scoped) [source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_importButton.enabled = YES;
            if (valid) {
                NSString *revisionName = revision[@"id"] ?: revision[@"name"] ?: @"development revision";
                self->_statusLabel.text = [NSString stringWithFormat:@"Game content imported (%@)", revisionName];
                [self refreshContentStatus];
            } else {
                NSString *message = error.localizedDescription ?: @"Import failed.";
                if (sha.length > 0 && error.code == 31) message = [message stringByAppendingFormat:@"\nExecutable SHA-256:\n%@", sha];
                self->_statusLabel.text = message;
            }
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { _statusLabel.text = @"Import cancelled."; }
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}
- (void)drawInMTKView:(MTKView *)view {
    if (!_commandQueue || !view.currentDrawable || !view.currentRenderPassDescriptor) return;
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Liberty Foundation Frame";
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
    encoder.label = @"Foundation Clear";
    [encoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}
@end

@interface LibertyAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation LibertyAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[LibertyShellViewController alloc] init];
    [self.window makeKeyAndVisible];
    NSLog(@"[Liberty] Foundation shell launched. app=%s upstream=%s", LIBERTY_BUILD_COMMIT, LIBERTY_UPSTREAM_COMMIT);
    return YES;
}
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window { return UIInterfaceOrientationMaskLandscape; }
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application { NSLog(@"[Liberty] iOS memory warning received."); }
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(LibertyAppDelegate.class)); }
}
