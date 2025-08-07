/**
 * iOS里kvo的封装有很多种方式，但是原理大同小异，就是用一个代理实现observeValueForKeyPath后，
 * 对实际观察者的方法或者block调用进行代理；
 * 代理的实现其实有两种，一种是对事件发送侧做代理，即在发送端挂代理对象，然后来分发事件；
 * 二是对接收测做代理，即在接收端挂代理对象，然后分发事件；FB的封装就是用的这种方法，现在改进后的封装也是用的这种；
 *
 * 对发送侧做代理呢，有个缺陷，就是发送侧是无法被动侦测接收方的GC的，即当接收者被GC了，
 * 发送侧无法被动通知来进行removeObserver，所以在系统里这个addObserver一直会被挂载在代理对象上，
 * 直到下一次的add/remove/notify事件来的时候，才会做一次主动侦测，这样的感觉还好，但是有点蛋疼；
 * 特别是对于客户端一般来说，其实 接收者的数量 是 远远小于发送者对象的数量的，比如，在数据侧，我们可以有很多条item或者数据；
 * 但是一般接收者为页面对象、或者列表item对象(可复用)，在数量级上会比发送者要低；
 * 所以经过权衡，如果大量的数据源挂载了空的observer代理，还是会有一些影响的；
 *
 * 在接受侧做代理，则无此缺陷，因为receiver在被回收时，是可以侦测到的，并主动调用removeObserver解绑代理和source；
 * 在source被回收时，更不用说了，挂载的所有observer也都烟消云散了；所以在接收侧做代理是比较优的做法；
 *
 * 这个缺陷，在Android端的kvo实现里同样存在，但是Android端的kvo整个流程不涉及到系统内部的api调用，全部由我们自己控制，
 * 所以问题和影响比iOS要小一些；
 *
 * 再说到FB的封装的缺陷，FB的缺陷是在于用一个FBShareController做了一个app域下的全局代理，
 * 这个是个全局锁，也是一个非常糟糕的设计；
 * 改进后，我们对每个receiver建立一个代理，然后通过sourceClass+source+selector/block+keypath来确定唯一的receiver接收，
 * 并使用读写锁，保证了在observeValueForKeyPath时的并发性能；这样既平衡了代理对象的数量，又可以保证性能；
 */
#import <pthread.h>
#import "KvoEventDispatcher.h"

static NSString * const LogTag = @"KvoEventDispatcher";

@implementation KvoEventIntent

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
    [description appendFormat:@"new: %@", self.nsNewValue];
    [description appendFormat:@", old: %@", self.nsOldValue];
    [description appendFormat:@", keyPath: %@", self.keyPath];
    [description appendFormat:@", source: %@", self.kvoSource];
    [description appendFormat:@", kind: %@", self.kind];
    [description appendFormat:@", indexes: %@", self.indexes];
    [description appendString:@">"];
    return description;
}

@end

@implementation KvoReceiver

- (nonnull instancetype)initWith:(nonnull NSObject *)source keyPath:(nonnull NSString *)keyPath
                  action:(nonnull SEL)invokeSel queue:(nullable dispatch_queue_t)queue {
    self = [super init];
    
    if (self) {
        _source = source;
        _keyPath = keyPath;
        _invokeSel = invokeSel;
        _queue = queue;
        _receiverHashCode = [NSString stringWithFormat:@"%@.%lu.%@.%@", [source class], source.hash, keyPath,
                             [NSString stringWithUTF8String:sel_getName(_invokeSel)]].hash;
    }
    
    return self;
}

- (instancetype)initWith:(nonnull NSObject *)source keyPath:(nonnull NSString *)keyPath
                   block:(nonnull KvoNotifyBlock)block queue:(nullable dispatch_queue_t)queue {
    self = [super init];
    
    if (self) {
        _source = source;
        _keyPath = keyPath;
        _block = block;
        _queue = queue;
        _receiverHashCode = [NSString stringWithFormat:@"%@.%lu.%@.%p", [source class], source.hash, keyPath, block].hash;
    }
    
    return self;
}

- (void)invoke:(nonnull KvoEventIntent *)intent to:(nonnull NSObject *)receiverObj {
    __weak KvoReceiver *weakSelf = self;
    
    if (_queue) {
        dispatch_async(_queue, ^{
            __strong KvoReceiver *strongSelf = weakSelf;
            
            if (strongSelf) {
                [strongSelf doInvoke:intent with:receiverObj];
            } else {
                NSLog(@"%@ KvoReceiver is dealloc when intent: %@", LogTag, intent);
            }
        });
    } else {
        [self doInvoke:intent with:receiverObj];
    }
}

- (void)doInvoke:(nonnull KvoEventIntent *)eventIntent with:(nonnull NSObject *)receiverObj {
    if (_invokeSel) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [receiverObj performSelector:_invokeSel withObject:eventIntent];
#pragma clang diagnostic pop
    } else {
        _block(eventIntent);
    }
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    
    if (!other || ![[other class] isEqual:[self class]]) {
        return NO;
    }
    
    KvoReceiver *otherReceiver = other;
    
    return _receiverHashCode == otherReceiver.receiverHashCode;
}

- (NSUInteger)hash {
    return _receiverHashCode;
}

- (nonnull NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
    [description appendFormat:@", sel: %p", self.invokeSel];
    [description appendFormat:@", block: %p", self.block];
    [description appendFormat:@", queue: %@", self.queue];
    [description appendFormat:@", hash: %lu", self.receiverHashCode];
    [description appendFormat:@", keyPath: %@", self.keyPath];
    [description appendString:@">"];
    return description;
}

@end

@interface KvoEventDispatcher ()

@property(nonatomic, weak, nullable) NSObject *receiverObj;

@property(nonatomic) pthread_rwlock_t lock;

@property(nonatomic, nonnull) NSMapTable<NSNumber *, KvoReceiver *> *connections;

@end

@implementation KvoEventDispatcher

- (nonnull instancetype)initWithReceiver:(nonnull NSObject *)receiverObj {
    self = [super init];
    
    if (self) {
        _receiverObj = receiverObj;
        
        _connections = [NSMapTable          mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                        | NSPointerFunctionsObjectPersonality valueOptions:NSPointerFunctionsStrongMemory
                        | NSPointerFunctionsObjectPersonality];
        
        pthread_rwlock_init(&_lock, NULL);
    }
    
    return self;
}

- (void)addBinding:(nonnull NSObject *)source to:(nonnull KvoReceiver *)receiver {
    __strong NSObject *strongReceiver = _receiverObj;
    
    if (!strongReceiver) {
        NSLog(@"%@ addBinding error receiver has been GC, receiver: %@", LogTag, receiver);
        [self releaseDispatcher];
        return;
    }
    
    NSUInteger key = receiver.receiverHashCode;
    
    pthread_rwlock_wrlock(&_lock);
    
    if ([_connections objectForKey:@(key)]) {
        pthread_rwlock_unlock(&_lock);
        return;
    }
    
    [_connections setObject:receiver forKey:@(key)];
    
    [source addObserver:self forKeyPath:receiver.keyPath
                options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew |
     NSKeyValueObservingOptionInitial context:(void *) key];
    
    pthread_rwlock_unlock(&_lock);
}

- (void)removeBinding:(nonnull NSObject *)source from:(nonnull KvoReceiver *)receiver {
    __strong NSObject *strongReceiver = _receiverObj;
    
    if (!strongReceiver) {
        NSLog(@"%@ removeBinding error receiver has been GC, receiver: %@", LogTag, receiver);
        [self releaseDispatcher];
        return;
    }
    
    NSUInteger key = receiver.receiverHashCode;
    
    pthread_rwlock_wrlock(&_lock);
    
    if (![_connections objectForKey:@(key)]) {
        pthread_rwlock_unlock(&_lock);
        return;
    }
    
    [_connections removeObjectForKey:@(key)];
    
    [source removeObserver:self forKeyPath:receiver.keyPath context:(void *) key];
    
    pthread_rwlock_unlock(&_lock);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    __strong NSObject *strongReceiver = _receiverObj;
    
    if (!strongReceiver) {
        NSLog(@"%@ observeValueForKeyPath error receiver has been GC", LogTag);
        [self releaseDispatcher];
        return;
    }
    
    pthread_rwlock_rdlock(&_lock);
    
    KvoReceiver *receiver = [_connections objectForKey:@((NSUInteger) context)];
    
    if (receiver) {
        pthread_rwlock_unlock(&_lock);
        
        KvoEventIntent *eventIntent = [[KvoEventIntent alloc] init];
        eventIntent.keyPath = keyPath;
        eventIntent.kvoSource = object;
        eventIntent.nsNewValue = change[NSKeyValueChangeNewKey];
        eventIntent.nsOldValue = change[NSKeyValueChangeOldKey];
        eventIntent.kind = change[NSKeyValueChangeKindKey];
        eventIntent.indexes = change[NSKeyValueChangeIndexesKey];
        
        [receiver invoke:eventIntent to:strongReceiver];
    } else {
        NSLog(@"%@ receiver not found but notify is coming, receiverObj:"
              "%@, keyPath: %@, source: %@", LogTag, strongReceiver, keyPath, object);
        
#ifdef ENTERPRISE_VERSION
        [NSException raise:NSInvalidArgumentException format:@"receiver not found but notify is coming, receiverObj:"
         "%@, keyPath: %@, source: %@", strongReceiver, keyPath, object];
#endif
        
        @try {
            //this would happen?
            [object removeObserver:self forKeyPath:keyPath context:context];
        } @catch (NSException *exception) {
            NSLog(@"%@ observeValueForKeyPath removeObserver error: %@", LogTag, exception);
        }
        
        pthread_rwlock_unlock(&_lock);
    }
}

- (void)releaseDispatcher {
    pthread_rwlock_wrlock(&_lock);
    
    for (KvoReceiver *receiver in _connections.objectEnumerator) {
        __strong NSObject *strongSource = receiver.source;
        
        if (strongSource) {
            [strongSource removeObserver:self forKeyPath:receiver.keyPath
                                 context:(void *) receiver.receiverHashCode];
        }
    }
    
    [_connections removeAllObjects];
    
    pthread_rwlock_unlock(&_lock);
}

- (void)dealloc {
    [self releaseDispatcher];
    
    pthread_rwlock_destroy(&_lock);
}

@end
