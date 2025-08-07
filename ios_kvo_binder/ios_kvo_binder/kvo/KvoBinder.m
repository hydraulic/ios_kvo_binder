#import "KvoBinder.h"
#import "NSObject+KvoEventDispatcher.h"

@interface KvoBinder ()

@property(nonatomic, nullable, weak) NSObject *target;

@property(nonatomic, nonnull) NSMutableDictionary<NSString *, NSObject *> *kvoSources;

@end

@implementation KvoBinder

-(nonnull instancetype)initWith:(nonnull NSObject*)receiverObj {
    self = [super init];
    
    if (self) {
        _target = receiverObj;
        _kvoSources = [NSMutableDictionary dictionary];
    }
    
    return self;
}

- (BOOL)singleBindTo:(nullable NSObject *)source {
    if (!source) {
        return NO;
    }
    
    return [self singleBind:[NSString stringWithFormat:@"%@", [source class]] to:source];
}

- (BOOL)singleBind:(nonnull NSString *)key to:(nullable NSObject *)source {
    if (!source) {
        return NO;
    }
    
    __strong NSObject *strongTarget = _target;
    
    if (!strongTarget) {
        HGLogError(@"KvoBinder", @"target has been GC");
        return NO;
    }
    
    @synchronized (self) {
        NSObject *oldSource = _kvoSources[key];
        
        if (oldSource == source) {
            return YES;
        }
        
        if (oldSource) {
            [strongTarget autoUnbind:source];
        }

        [strongTarget autoBind:source];

        _kvoSources[key] = source;
    }
    
    return YES;
}

-(void)clearKvoConnection:(nonnull NSString *)key {
    __strong NSObject *strongTarget = _target;

    if (!strongTarget) {
        return;
    }

    @synchronized (self) {
        NSObject *source = _kvoSources[key];

        if (source) {
            [_kvoSources removeObjectForKey:key];

            [strongTarget autoUnbind:source];
        }
    }
}

- (void)clearAllKvoConnections {
    __strong NSObject *strongTarget = _target;

    if (!strongTarget) {
        return;
    }

    @synchronized (self) {
        for (NSObject *source in _kvoSources.objectEnumerator) {
            [strongTarget autoUnbind:source];
        }

        [_kvoSources removeAllObjects];
    }
}

-(void)dealloc {
    @synchronized (self) {
        [_kvoSources removeAllObjects];
    }
}

@end
