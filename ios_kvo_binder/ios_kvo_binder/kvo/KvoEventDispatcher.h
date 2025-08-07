//
// Created by hydra on 2021/12/3.
//

#import <Foundation/Foundation.h>

@class KvoEventIntent;

typedef void (^KvoNotifyBlock)(KvoEventIntent *_Nonnull intent);

@interface KvoEventIntent : NSObject

@property(nonatomic, nullable) id nsNewValue;
@property(nonatomic, nullable) id nsOldValue;
@property(nonatomic, nonnull) NSString *keyPath;
@property(nonatomic, nonnull) NSObject *kvoSource;  //这个不用weak

//for collection
@property(nonatomic, nullable) NSNumber *kind;
@property(nonatomic, nullable) NSIndexSet *indexes;

@end

@interface KvoReceiver : NSObject

@property(nonatomic, readonly, nonnull) NSString *keyPath;

@property(nonatomic, nullable, weak) NSObject *source;

@property(nonatomic, readonly, nullable) SEL invokeSel;

@property(nonatomic, readonly, nullable) KvoNotifyBlock block;

@property(nonatomic, readonly) NSUInteger receiverHashCode;

@property(nonatomic, readonly, nullable) dispatch_queue_t queue;

- (nonnull instancetype)initWith:(nonnull NSObject *)source keyPath:(nonnull NSString *)keyPath
                          action:(nonnull SEL)invokeSel
                           queue:(nullable dispatch_queue_t)queue;

- (nonnull instancetype)initWith:(nonnull NSObject *)source keyPath:(nonnull NSString *)keyPath
                           block:(nonnull KvoNotifyBlock)block
                           queue:(nullable dispatch_queue_t)queue;

- (void)invoke:(nonnull KvoEventIntent *)intent to:(nonnull NSObject *)receiverObj;

@end

@interface KvoEventDispatcher : NSObject

- (void)addBinding:(nonnull NSObject *)source to:(nonnull KvoReceiver *)receiver;

- (void)removeBinding:(nonnull NSObject *)source from:(nonnull KvoReceiver *)receiver;

- (nonnull instancetype)initWithReceiver:(nonnull NSObject *)receiverObj;

@end
