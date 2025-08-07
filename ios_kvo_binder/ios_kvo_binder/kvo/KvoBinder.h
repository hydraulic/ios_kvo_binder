//
// 和Android端的KvoBinder用途一样
//
//
#import <Foundation/Foundation.h>

@interface KvoBinder : NSObject

//
//要配合autoBind和Kvo_Handle_Notify宏一起使用
//
- (nonnull instancetype)initWith:(nonnull NSObject *)receiverObj;

- (BOOL)singleBindTo:(nullable NSObject *)source;

- (BOOL)singleBind:(nonnull NSString *)key to:(nullable NSObject *)source;

- (void)clearKvoConnection:(nonnull NSString *)key;

- (void)clearAllKvoConnections;

@end
