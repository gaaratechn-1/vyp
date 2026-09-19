#import "mcm_bridge.h"
#import <dlfcn.h>
#import <fcntl.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/stat.h>
#import <xpc/xpc.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Definiciones de tipos para libsystem_containermanager (Método 3105)
typedef void *(*MCMQueryCreate)(void);
typedef void (*MCMQuerySetU64)(void *, uint64_t);
typedef void (*MCMQuerySetXPC)(void *, xpc_object_t);
typedef void *(*MCMQueryGetPointer)(void *);
typedef bool (*MCMQueryIterate)(void *, bool (^)(void *));
typedef char *(*MCMCopyToken)(void *);
typedef const char *(*MCMGetPath)(void *);
typedef const char *(*MCMGetIdentifier)(void *);
typedef void *(*MCMObjectCopy)(void *);
typedef bool (*MCMObjectActivate)(void *, bool);
typedef void (*MCMObjectFree)(void *);
typedef int (*MCMErrorGetInt)(void *);
typedef const char *(*MCMErrorGetString)(void *);
typedef void (*MCMQueryFree)(void *);

typedef struct {
    void *handle;
    MCMQueryCreate queryCreate;
    MCMQuerySetU64 querySetClass;
    MCMQuerySetXPC querySetIdentifiers;
    MCMQuerySetXPC querySetGroupIdentifiers;
    MCMQuerySetU64 querySetFlags;
    MCMQuerySetU64 querySetPart;
    MCMQueryGetPointer queryGetSingle;
    MCMQueryGetPointer queryGetLastError;
    MCMQueryIterate queryIterate;
    MCMQueryFree queryFree;
    MCMGetPath objectGetPath;
    MCMGetIdentifier objectGetIdentifier;
    MCMObjectCopy objectCopy;
    MCMCopyToken objectCopyToken;
    MCMObjectActivate objectActivate;
    MCMObjectFree objectFree;
    MCMErrorGetInt errorGetPOSIX;
    MCMErrorGetString errorGetMessage;
} MCMSharedState;

static MCMSharedState *MCMGetAPI(void) {
    static MCMSharedState api;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        api.handle = dlopen(
            "/usr/lib/system/libsystem_containermanager.dylib",
            RTLD_NOW | RTLD_LOCAL
        );
        void *h = api.handle ?: RTLD_DEFAULT;
        
        #define RESOLVE(f, s) api.f = (__typeof(api.f))dlsym(h, s)
        RESOLVE(queryCreate, "container_query_create");
        RESOLVE(querySetClass, "container_query_set_class");
        RESOLVE(querySetIdentifiers, "container_query_set_identifiers");
        RESOLVE(querySetGroupIdentifiers, "container_query_set_group_identifiers");
        RESOLVE(querySetFlags, "container_query_operation_set_flags");
        RESOLVE(querySetPart, "container_query_operation_set_part");
        RESOLVE(queryGetSingle, "container_query_get_single_result");
        RESOLVE(queryGetLastError, "container_query_get_last_error");
        RESOLVE(queryIterate, "container_query_iterate_results_sync");
        RESOLVE(queryFree, "container_query_free");
        RESOLVE(objectGetPath, "container_object_get_path");
        RESOLVE(objectGetIdentifier, "container_object_get_identifier");
        RESOLVE(objectCopy, "container_object_copy");
        RESOLVE(objectCopyToken, "container_copy_sandbox_token");
        RESOLVE(objectActivate, "container_object_sandbox_extension_activate");
        RESOLVE(objectFree, "container_object_free");
        RESOLVE(errorGetPOSIX, "container_error_get_posix_errno");
        RESOLVE(errorGetMessage, "container_error_get_message");
        #undef RESOLVE
    });
    return &api;
}

BOOL MCMBridgeAvailable(void) {
    MCMSharedState *api = MCMGetAPI();
    return (api->queryCreate && api->querySetClass &&
            api->querySetIdentifiers && api->querySetGroupIdentifiers &&
            api->querySetFlags && api->queryGetSingle && api->queryFree &&
            api->objectGetPath && api->objectCopy && api->objectCopyToken &&
            api->objectActivate && api->objectFree);
}

static BOOL MCMSafeIdentifier(NSString *ident) {
    if (!ident || ident.length == 0 || ident.length > 255) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    return [ident rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound &&
        ![ident isEqualToString:@"."] && ![ident isEqualToString:@".."];
}

// Implementación exacta de MCMRetainedLease de 3105
@interface MCMRetainedLease : NSObject {
    void *_query;
    void *_activation;
}
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic) BOOL activated;
+ (nullable instancetype)leaseForClass:(uint64_t)cls
                             identifier:(NSString *)identifier
                                  group:(BOOL)group
                                  error:(NSString **)error;
- (BOOL)activate:(NSString **)error;
@end

@implementation MCMRetainedLease

+ (instancetype)leaseForClass:(uint64_t)cls
                    identifier:(NSString *)identifier
                         group:(BOOL)group
                         error:(NSString **)error {
    MCMSharedState *api = MCMGetAPI();
    if (!MCMBridgeAvailable() || !MCMSafeIdentifier(identifier)) {
        if (error) *error = @"MCM unavailable or identifier contains unsupported characters";
        return nil;
    }

    void *query = api->queryCreate();
    if (!query) {
        if (error) *error = @"query create failed";
        return nil;
    }

    api->querySetClass(query, cls);
    xpc_object_t value = xpc_string_create(identifier.UTF8String);
    if (group) api->querySetGroupIdentifiers(query, value);
    else api->querySetIdentifiers(query, value);
#if !OS_OBJECT_USE_OBJC
    xpc_release(value);
#endif
    // En 3105, 0x900000000ULL solicita la extensión de sandbox adecuada
    api->querySetFlags(query, 0x900000000ULL);
    if (api->querySetPart) api->querySetPart(query, 0);

    void *result = api->queryGetSingle(query);
    if (!result) {
        void *queryError = api->queryGetLastError ? api->queryGetLastError(query) : NULL;
        int posix = queryError && api->errorGetPOSIX ? api->errorGetPOSIX(queryError) : 0;
        const char *message = queryError && api->errorGetMessage
            ? api->errorGetMessage(queryError) : NULL;
        if (error) *error = [NSString stringWithFormat:@"lookup denied posix=%d message=%s",
            posix, message ?: "unknown"];
        api->queryFree(query);
        return nil;
    }

    const char *rawPath = api->objectGetPath(result);
    NSString *rootPath = rawPath ? [NSString stringWithUTF8String:rawPath] : nil;
    if (rootPath.length == 0 || !rootPath.isAbsolutePath) {
        if (error) *error = @"MCM returned no absolute container path";
        api->queryFree(query);
        return nil;
    }
    if ([rootPath isEqualToString:@"/var"] || [rootPath hasPrefix:@"/var/"]) {
        rootPath = [@"/private" stringByAppendingString:rootPath];
    }

    MCMRetainedLease *lease = [MCMRetainedLease new];
    lease->_query = query;
    lease.rootPath = rootPath;
    return lease;
}

- (BOOL)activate:(NSString **)error {
    if (self.activated) return YES;
    if (!_query) {
        if (error) *error = @"lease invalidated";
        return NO;
    }

    MCMSharedState *api = MCMGetAPI();
    void *result = api->queryGetSingle(_query);
    _activation = result ? api->objectCopy(result) : NULL;
    char *token = _activation ? api->objectCopyToken(_activation) : NULL;
    BOOL tokenPresent = token && token[0] != '\0';
    if (token) free(token);
    self.activated = tokenPresent && api->objectActivate(_activation, false);
    if (!self.activated && error) {
        *error = tokenPresent
            ? @"sandbox extension activation failed"
            : @"MCM object contained no sandbox token";
    }
    return self.activated;
}

- (void)dealloc {
    MCMSharedState *api = MCMGetAPI();
    if (_activation && api->objectFree) api->objectFree(_activation);
    if (_query && api->queryFree) api->queryFree(_query);
}

@end

static NSMutableDictionary<NSString *, MCMRetainedLease *> *MCMActiveLeases(void) {
    static NSMutableDictionary<NSString *, MCMRetainedLease *> *leases;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        leases = [NSMutableDictionary dictionary];
    });
    return leases;
}

NSArray<NSString *> *MCMEnumerateIdentifiersForClass(uint64_t cls, NSUInteger limit, NSString **error) {
    MCMSharedState *api = MCMGetAPI();
    if (!api->queryCreate || !api->querySetClass || !api->querySetFlags ||
        !api->queryIterate || !api->objectGetIdentifier || !api->queryFree ||
        limit == 0) {
        if (error) *error = @"missing symbols";
        return @[];
    }

    void *query = api->queryCreate();
    if (!query) { if (error) *error = @"query create failed"; return @[]; }

    api->querySetClass(query, cls);
    api->querySetFlags(query, 0x100000000ULL);
    if (api->querySetPart) api->querySetPart(query, 0);

    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    BOOL iterated = api->queryIterate(query, ^bool(void *object) {
        const char *raw = object ? api->objectGetIdentifier(object) : NULL;
        NSString *identifier = raw ? [NSString stringWithUTF8String:raw] : nil;
        if (identifier.length && MCMSafeIdentifier(identifier)) {
            [set addObject:identifier];
        }
        return set.count < limit;
    });
    if (!iterated && set.count < limit && error) {
        void *queryError = api->queryGetLastError ? api->queryGetLastError(query) : NULL;
        int posix = queryError && api->errorGetPOSIX ? api->errorGetPOSIX(queryError) : 0;
        const char *message = queryError && api->errorGetMessage
            ? api->errorGetMessage(queryError) : NULL;
        *error = [NSString stringWithFormat:@"enumeration denied posix=%d message=%s",
            posix, message ?: "unknown"];
    }

    api->queryFree(query);
    return set.array;
}

NSString *MCMActivateContainerPath(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    if (!MCMSafeIdentifier(identifier)) {
        if (error) *error = @"identifier contains unsupported characters";
        return nil;
    }

    NSMutableDictionary *leases = MCMActiveLeases();
    NSString *key = [NSString stringWithFormat:@"%llu:%d:%@", cls, group, identifier];
    @synchronized (leases) {
        MCMRetainedLease *existing = leases[key];
        if (existing.rootPath.length) return existing.rootPath;

        NSString *detail = nil;
        MCMRetainedLease *lease = [MCMRetainedLease leaseForClass:cls
            identifier:identifier group:group error:&detail];
        if (!lease) {
            if (error) *error = detail ?: @"MCM lookup failed";
            return nil;
        }
        [lease activate:&detail];

        int descriptor = open(
            lease.rootPath.fileSystemRepresentation,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        );
        if (descriptor < 0) {
            if (error) {
                *error = detail ?: [NSString stringWithFormat:
                    @"container root open failed errno=%d", errno];
            }
            return nil;
        }
        close(descriptor);
        leases[key] = lease;
        return lease.rootPath;
    }
}

int64_t MCMActivateContainer(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    return MCMActivateContainerPath(cls, identifier, group, error) ? 1 : -1;
}

// MARK: - Inode Directory Enumeration (Método 3105 fsgetpath / bad_query_list)
#import <sys/mount.h>
#if __has_include(<sys/fsgetpath.h>)
#import <sys/fsgetpath.h>
#else
extern ssize_t fsgetpath(char *buf, size_t bufsize, fsid_t *fsid, uint64_t objid);
#endif

NSArray<NSString *> *MCMEnumerateDirectoriesViaFSGetPath(NSString *basePath, int64_t maxInode) {
    if (!basePath || basePath.length == 0) return @[];
    const char *path = basePath.fileSystemRepresentation;
    struct statfs sfs;
    if (statfs(path, &sfs) != 0) return @[];
    fsid_t fsid = sfs.f_fsid;

    NSMutableArray<NSString *> *results = [NSMutableArray array];
    size_t path_length = strlen(path);
    char buf[1200];
    if (maxInode <= 0) maxInode = 2000000;

    for (uint64_t ino = 1; ino <= (uint64_t)maxInode; ino++) {
        ssize_t n = fsgetpath(buf, sizeof(buf), &fsid, ino);
        if (n <= 0) continue;

        const char *p = buf;
        if (strncmp(p, "/private/var/", 13) == 0) p += 8;
        if (strncmp(p, path, path_length) != 0 || p[path_length] != '/') continue;
        if (strchr(p + path_length + 1, '/')) continue;

        NSString *dir = [NSString stringWithUTF8String:p];
        if (dir.length) {
            [results addObject:dir];
        }
    }
    return [results copy];
}


// MARK: - 3105 LaunchServices & MobileInstallation Discovery Bridge

static NSString *stringForFirstKey(NSDictionary *info, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = info[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static NSString *pathForFirstKey(NSDictionary *info, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = info[key];
        if ([value isKindOfClass:[NSURL class]]) {
            NSString *path = [value path];
            if (path.length > 0) return path;
        }
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static void ensureLaunchServicesLoaded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *candidates[] = {
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
            "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            if (dlopen(candidates[i], RTLD_LAZY | RTLD_GLOBAL)) {
                return;
            }
        }
    });
}

static NSDictionary *appsFromWorkspace(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    ensureLaunchServicesLoaded();

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return result;
    SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
    if (![workspaceClass respondsToSelector:defaultWorkspaceSel]) return result;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspaceSel);
    if (!workspace) return result;

    NSArray *apps = nil;
    for (NSString *selectorName in @[@"allApplications", @"allInstalledApplications"]) {
        SEL allAppsSel = NSSelectorFromString(selectorName);
        if (![workspace respondsToSelector:allAppsSel]) continue;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, allAppsSel);
        if ([candidate isKindOfClass:[NSArray class]] && [candidate count] > 0) {
            apps = candidate;
            break;
        }
    }
    if (!apps || apps.count == 0) return result;

    for (id app in apps) {
        @autoreleasepool {
            NSString *bundleID = nil;
            for (NSString *selectorName in @[@"bundleIdentifier", @"applicationIdentifier"]) {
                SEL bundleSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:bundleSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, bundleSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    bundleID = value;
                    break;
                }
            }
            if (bundleID.length == 0) continue;

            NSString *name = nil;
            for (NSString *selectorName in @[@"localizedName", @"localizedShortName"]) {
                SEL nameSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:nameSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, nameSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    name = value;
                    break;
                }
            }
            if (name.length == 0) name = bundleID;

            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = name;
            for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
                SEL containerSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:containerSel]) continue;
                id containerValue = ((id (*)(id, SEL))objc_msgSend)(app, containerSel);
                NSString *containerPath = [containerValue isKindOfClass:[NSURL class]] ? [containerValue path] : containerValue;
                if ([containerPath isKindOfClass:[NSString class]] && containerPath.length > 0) {
                    entry[@"container"] = containerPath;
                    break;
                }
            }
            result[bundleID] = entry;
        }
    }
    return result;
}

static NSDictionary *appsFromMobileInstallation(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    void *frameworkHandle = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY | RTLD_LOCAL);

    void *lookupFn = dlsym(RTLD_DEFAULT, "MobileInstallationLookup");
    if (!lookupFn && frameworkHandle) {
        lookupFn = dlsym(frameworkHandle, "MobileInstallationLookup");
    }
    if (!lookupFn) return result;

    NSDictionary *apps = nil;
    NSArray *optionSets = @[
        @{@"ApplicationType": @"Any"},
        @{@"ApplicationType": @"User"},
        @{@"ApplicationType": @"System"},
        @{},
    ];
    for (NSDictionary *options in optionSets) {
        apps = ((NSDictionary *(*)(NSDictionary *, void *))lookupFn)(options, NULL);
        if (apps && [apps isKindOfClass:[NSDictionary class]] && apps.count > 0) break;
    }
    if (!apps || apps.count == 0) return result;

    for (NSString *bundleID in apps) {
        @autoreleasepool {
            id rawInfo = apps[bundleID];
            if (![rawInfo isKindOfClass:[NSDictionary class]]) continue;
            NSString *name = stringForFirstKey(rawInfo, @[@"CFBundleDisplayName", @"CFBundleName", @"LocalizedName"]);
            NSString *container = pathForFirstKey(rawInfo, @[@"Container", @"DataContainer", @"DataContainerURL", @"ContainerPath"]);
            NSString *version = stringForFirstKey(rawInfo, @[@"CFBundleShortVersionString", @"BundleShortVersionString"]);
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = name.length > 0 ? name : bundleID;
            if (container.length > 0) entry[@"container"] = container;
            if (version.length > 0) entry[@"version"] = version;
            result[bundleID] = entry;
        }
    }
    return result;
}

NSDictionary<NSString *, NSDictionary *> *MCMInstalledAppInfo(void) {
    NSMutableDictionary *combined = [NSMutableDictionary dictionary];
    NSDictionary *mobileInstallation = appsFromMobileInstallation();
    if (mobileInstallation.count > 0) {
        [combined addEntriesFromDictionary:mobileInstallation];
    }
    NSDictionary *workspace = appsFromWorkspace();
    if (workspace.count > 0) {
        [combined addEntriesFromDictionary:workspace];
    }
    return [combined copy];
}

NSDictionary *MCMAppInfoForBundleID(NSString *bundleID) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"name"] = bundleID;
    if (bundleID.length == 0) return result;

    ensureLaunchServicesLoaded();
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (!proxyClass) return result;
    SEL appProxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![proxyClass respondsToSelector:appProxySel]) return result;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, appProxySel, bundleID);
    if (!proxy) return result;

    for (NSString *selectorName in @[@"localizedName", @"localizedShortName"]) {
        SEL nameSel = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:nameSel]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(proxy, nameSel);
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            result[@"name"] = value;
            break;
        }
    }

    for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
        SEL containerSel = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:containerSel]) continue;
        id containerValue = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSel);
        NSString *containerPath = [containerValue isKindOfClass:[NSURL class]] ? [containerValue path] : containerValue;
        if ([containerPath isKindOfClass:[NSString class]] && containerPath.length > 0) {
            result[@"container"] = containerPath;
            break;
        }
    }
    return result;
}

