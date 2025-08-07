//
//  HGThreadBus.h
//  pkgame iOS
//
//  Created by KAIBIN WU on 2018/11/23.
//

#import <Foundation/Foundation.h>

// 线程索引
typedef enum : NSUInteger {
    ThreadMain,
    ThreadWhatEver,
    ThreadIO,
    ThreadNet,
    ThreadDb,
    ThreadWorking,    //用户发起需要马上得到结果进行后续任务, 对应DISPATCH_QUEUE_PRIORITY_HIGH
    ThreadBackground, //在后台的操作可能需要好几分钟甚至几小时的，对应DISPATCH_QUEUE_PRIORITY_BACKGROUND
    ThreadLog,
    ThreadMax,
} HGThreadTag;

/**
 每个串行队列对应一个系统线程，这些线程都是并行执行的，只是串行队列中的任务是串行执行的，从而保证线程安全
 */
@interface HGThreadBus : NSObject

- (void)startup;

- (void)post:(dispatch_block_t)block to:(int)thread;

- (void)post:(dispatch_block_t)block to:(int)thread dealyed:(NSTimeInterval)deal;

- (void)post:(dispatch_block_t)block to:(int)thread atTime:(NSTimeInterval)uptime;

- (void)callsafe:(dispatch_block_t)block inThread:(int)thread;

- (void)setQueue:(dispatch_queue_t)queue toThread:(int)thread;

- (dispatch_queue_t)queueOf:(int)thread;

+ (instancetype)sharedInstance;

@end
