//
//  HGThreadBus.m
//  pkgame iOS
//
//  Created by KAIBIN WU on 2018/11/23.
//

#import "HGThreadBus.h"

#define LOCK(lock) dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
#define UNLOCK(lock) dispatch_semaphore_signal(lock);

@interface HGThreadBus ()
{
    dispatch_queue_t _queues[ThreadMax];
    dispatch_semaphore_t _lock;
}

@end


@implementation HGThreadBus

- (void)startup
{
    _queues[ThreadMain] = dispatch_get_main_queue();
    _queues[ThreadWhatEver] = dispatch_queue_create("ThreadBus-WhatEver", NULL);
    _queues[ThreadIO] = dispatch_queue_create("ThreadBus-IO", NULL);
    _queues[ThreadNet] = dispatch_queue_create("ThreadBus-Net", NULL);
    _queues[ThreadDb] = dispatch_queue_create("ThreadBus-Db", NULL);
    _queues[ThreadWorking] = dispatch_queue_create("ThreadBus-Woring", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    _queues[ThreadBackground] = dispatch_queue_create("ThreadBus-Background", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0));
    _queues[ThreadLog] = dispatch_queue_create("ThreadBus-Log", NULL);
    _lock = dispatch_semaphore_create(1);
}

- (void)setQueue:(dispatch_queue_t)queue toThread:(int)thread
{
    LOCK(_lock)
    _queues[thread] = queue;
    UNLOCK(_lock)
}

- (dispatch_queue_t)queueOf:(int)thread
{
    LOCK(_lock)
    dispatch_queue_t queue = _queues[thread];
    UNLOCK(_lock)
    return queue;
}

- (void)post:(dispatch_block_t)block to:(int)thread
{
    dispatch_queue_t queue = [self queueOf:thread];

    // the sync way will easy to cause dead-block
    dispatch_async(queue, block);
}

- (void)post:(dispatch_block_t)block to:(int)thread dealyed:(NSTimeInterval)delay
{
    dispatch_queue_t queue = [self queueOf:thread];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, block);
}

- (void)post:(dispatch_block_t)block to:(int)thread atTime:(NSTimeInterval)uptime
{
    dispatch_queue_t queue = [self queueOf:thread];

    dispatch_after((int64_t)(uptime * NSEC_PER_SEC), queue, block);
}

- (void)callsafe:(dispatch_block_t)block inThread:(int)thread
{
    // whatever
    if (thread == ThreadWhatEver) {
        block();
        return;
    }

    dispatch_queue_t queue = [self queueOf:thread];

    // main thread
    if (thread == ThreadMain && [NSThread isMainThread]) {
        block();
        return;
    }

    // the sync way will easy to cause dead-block
    dispatch_async(queue, block);
}


+ (instancetype)sharedInstance
{
    static dispatch_once_t once;
    static HGThreadBus *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [HGThreadBus new];
        [sharedInstance startup];
    });
    return sharedInstance;
}

@end
