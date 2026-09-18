#import "mcm_bridge.h"
#import <dlfcn.h>
#import <fcntl.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/stat.h>
#import <xpc/xpc.h>

// Definiciones de tipos para libsystem_containermanager
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
typedef int64_t (*SandboxExtensionConsume)(const char *);
typedef int (*SandboxExtensionRelease)(int64_t);

typedef struct {
    void *handle;
    MCMQueryCreate queryCreate;
    MCMQuerySetU64 querySetClass;
    MCMQuerySetXPC querySetIdentifiers;
    MCMQuerySetXPC querySetGroupIdentifiers;
    MCMQuerySetU64 querySetFlags;
    MCMQueryGetPointer queryGetSingle;
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
    SandboxExtensionConsume extensionConsume;
    SandboxExtensionRelease extensionRelease;
} MCMSharedState;

static MCMSharedState *MCMGetAPI(void) {
    static MCMSharedState api;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        api.handle = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
        void *h = api.handle ?: RTLD_DEFAULT;
        
        #define RESOLVE(f, s) api.f = (__typeof(api.f))dlsym(h, s)
        RESOLVE(queryCreate, "container_query_create");
        RESOLVE(querySetClass, "container_query_set_class");
        RESOLVE(querySetIdentifiers, "container_query_set_identifiers");
        RESOLVE(querySetGroupIdentifiers, "container_query_set_group_identifiers");
        RESOLVE(querySetFlags, "container_query_operation_set_flags");
        RESOLVE(queryGetSingle, "container_query_get_single_result");
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
        RESOLVE(extensionConsume, "sandbox_extension_consume");
        RESOLVE(extensionRelease, "sandbox_extension_release");
        #undef RESOLVE
    });
    return &api;
}

BOOL MCMBridgeAvailable(void) {
    MCMSharedState *api = MCMGetAPI();
    return (api->queryCreate && api->querySetClass && api->queryGetSingle &&
            api->objectGetPath && api->objectActivate && api->queryFree);
}

static BOOL MCMSafeIdentifier(NSString *ident) {
    if (!ident || ident.length == 0 || ident.length > 255) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    return [ident rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

@interface MCMRetainedLease : NSObject
@property (nonatomic, assign) void *containerObject;
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic, assign) int64_t extensionHandle;
@end

@implementation MCMRetainedLease
- (void)dealloc {
    MCMSharedState *api = MCMGetAPI();
    if (_extensionHandle > 0 && api->extensionRelease) {
        api->extensionRelease(_extensionHandle);
    }
    if (_containerObject && api->objectFree) {
        api->objectFree(_containerObject);
    }
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
    if (!MCMBridgeAvailable() || !api->queryIterate || !api->objectGetIdentifier) {
        if (error) *error = @"MCM bridge symbols unavailable";
        return @[];
    }
    
    void *query = api->queryCreate();
    if (!query) {
        if (error) *error = @"Failed to create container query";
        return @[];
    }
    
    api->querySetClass(query, cls);
    api->querySetFlags(query, 0x100000000ULL);
    
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    api->queryIterate(query, ^bool(void *item) {
        if (!item) return false;
        const char *identStr = api->objectGetIdentifier(item);
        if (identStr) {
            NSString *s = [NSString stringWithUTF8String:identStr];
            if (s && MCMSafeIdentifier(s)) {
                [result addObject:s];
            }
        }
        return result.count < limit;
    });
    
    api->queryFree(query);
    return [result copy];
}

NSString *MCMActivateContainerPath(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    // Verificación de identificador seguro
    if (!MCMSafeIdentifier(identifier)) {
        if (error) *error = @"Invalid bundle identifier characters";
        return nil;
    }
    
    MCMSharedState *api = MCMGetAPI();
    if (!MCMBridgeAvailable()) {
        if (error) *error = @"libsystem_containermanager symbols missing";
        return nil;
    }
    
    NSMutableDictionary *leases = MCMActiveLeases();
    NSString *cacheKey = [NSString stringWithFormat:@"%llu:%d:%@", cls, group, identifier];
    
    @synchronized (leases) {
        MCMRetainedLease *cached = leases[cacheKey];
        if (cached && cached.rootPath.length > 0) {
            // Verificar si sigue accesible en el FS
            if (access(cached.rootPath.fileSystemRepresentation, R_OK) == 0) {
                return cached.rootPath;
            }
        }
        
        void *query = api->queryCreate();
        if (!query) {
            if (error) *error = @"container_query_create returned null";
            return nil;
        }
        
        api->querySetClass(query, cls);
        xpc_object_t arr = xpc_array_create_empty();
        xpc_array_set_string(arr, XPC_ARRAY_APPEND, identifier.UTF8String);
        if (group && api->querySetGroupIdentifiers) {
            api->querySetGroupIdentifiers(query, arr);
        } else if (api->querySetIdentifiers) {
            api->querySetIdentifiers(query, arr);
        }
        
        void *singleResult = api->queryGetSingle(query);
        if (!singleResult) {
            api->queryFree(query);
            if (error) *error = [NSString stringWithFormat:@"Container for %@ not found", identifier];
            return nil;
        }
        
        void *copiedObj = api->objectCopy ? api->objectCopy(singleResult) : singleResult;
        api->queryFree(query);
        
        if (!copiedObj) {
            if (error) *error = @"Failed to copy container object";
            return nil;
        }
        
        // Activar token de sandbox para el proceso actual
        if (api->objectActivate) {
            api->objectActivate(copiedObj, true);
        }
        
        int64_t handle = -1;
        if (api->objectCopyToken && api->extensionConsume) {
            char *token = api->objectCopyToken(copiedObj);
            if (token) {
                handle = api->extensionConsume(token);
                free(token);
            }
        }
        
        const char *rawPath = api->objectGetPath(copiedObj);
        if (!rawPath) {
            if (api->objectFree) api->objectFree(copiedObj);
            if (error) *error = @"Container path pointer is null";
            return nil;
        }
        
        NSString *path = [NSString stringWithUTF8String:rawPath];
        
        // Comprobar descriptor de archivo para verificar acceso real
        int fd = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        if (fd < 0) {
            // Intentar verificar con stat
            struct stat st;
            if (stat(path.fileSystemRepresentation, &st) != 0) {
                if (api->objectFree) api->objectFree(copiedObj);
                if (error) *error = [NSString stringWithFormat:@"Container inaccessible (errno=%d)", errno];
                return nil;
            }
        } else {
            close(fd);
        }
        
        MCMRetainedLease *lease = [[MCMRetainedLease alloc] init];
        lease.containerObject = copiedObj;
        lease.rootPath = path;
        lease.extensionHandle = handle;
        leases[cacheKey] = lease;
        
        return path;
    }
}

int64_t MCMActivateContainer(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    NSString *path = MCMActivateContainerPath(cls, identifier, group, error);
    return path ? 1 : -1;
}
