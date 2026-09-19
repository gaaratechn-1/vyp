#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MCMBridge: Acceso directo a libsystem_containermanager.dylib para manipulación
 * de sandbox de aplicaciones en dispositivos iOS mediante MobileHouseArrest (MHA-C2).
 */

/// Comprueba si los símbolos del sistema de libsystem_containermanager están disponibles.
BOOL MCMBridgeAvailable(void);

/// Enumera los identificadores registrados para una clase de contenedor dada (Clase 2 = App Data).
NSArray<NSString *> *MCMEnumerateIdentifiersForClass(
    uint64_t cls,
    NSUInteger limit,
    NSString * _Nullable * _Nullable error
);

/// Activa y retorna la ruta absoluta en disco del contenedor para un identificador dado.
/// Clase 2: Aplicaciones (/var/mobile/Containers/Data/Application/<UUID>)
/// Clase 4: App Groups (/var/mobile/Containers/Shared/AppGroup/<UUID>)
NSString * _Nullable MCMActivateContainerPath(
    uint64_t cls,
    NSString *identifier,
    BOOL group,
    NSString * _Nullable * _Nullable error
);

/// Consume el token de extensión de sandbox y retorna 1 en caso de éxito.
int64_t MCMActivateContainer(
    uint64_t cls,
    NSString *identifier,
    BOOL group,
    NSString * _Nullable * _Nullable error
);

/// Retorna información de aplicaciones instaladas (LaunchServices / MobileInstallation).
/// Mapeo bundleID -> @{ @"name": NSString, @"container": NSString, @"version": NSString }
NSDictionary<NSString *, NSDictionary *> *MCMInstalledAppInfo(void);

/// Retorna @{ @"name": NSString, @"container": NSString } para un bundle ID vía LSApplicationProxy.
NSDictionary *MCMAppInfoForBundleID(NSString *bundleID);

/// Enumera directorios en una ruta mediante fsgetpath (método 3105 bad_query_list para saltar restricciones de sandbox en /var/mobile/Containers/Data/Application)
NSArray<NSString *> *MCMEnumerateDirectoriesViaFSGetPath(NSString *basePath, int64_t maxInode);

NS_ASSUME_NONNULL_END

