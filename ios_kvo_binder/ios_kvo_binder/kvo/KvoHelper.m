//
// Created by hydra on 2021/12/2.
//

#import <objc/runtime.h>
#import "KvoHelper.h"
#import "pthread.h"
#import "HGThreadBus.h"

static NSString * const LogTag = @"KvoHelper";

@implementation KvoMethodNode

@end

@interface KvoHelper ()

@property(nonatomic, nonnull, readonly) NSMapTable<Class, NSMutableSet<NSString *> *> *clazzProperties;

@property(nonatomic, nonnull, readonly) NSMapTable<NSString *, NSMutableArray<KvoMethodNode *> *> *clazzSelectors;

@property(nonatomic) pthread_rwlock_t lock;

@property(nonatomic) pthread_rwlock_t selectorLock;

//保存HGThreadBus的名字信息
@property(nonatomic, nonnull, readonly) NSMapTable<NSString *, NSNumber *> *HGThreadBusNames;

//系统类名
@property(nonatomic, nonnull, readonly) NSSet<NSString *> *systemClasses;

@end

@implementation KvoHelper

- (instancetype)init {
    self = [super init];
    
    if (self) {
        _clazzProperties = [NSMapTable strongToStrongObjectsMapTable];
        _clazzSelectors = [NSMapTable strongToStrongObjectsMapTable];
        
        pthread_rwlock_init(&_lock, NULL);
        pthread_rwlock_init(&_selectorLock, NULL);
        
        [self initThreadBusNames];
        
        [self initSystemClasses];
    }
    
    return self;
}

+ (nonnull instancetype)sharedInstance {
    static id _sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    
    return _sharedInstance;
}

- (void)initThreadBusNames {
    _HGThreadBusNames = [NSMapTable strongToStrongObjectsMapTable];
    
    [_HGThreadBusNames setObject:@(ThreadWhatEver) forKey:@"ThreadWhatEver"];
    [_HGThreadBusNames setObject:@(ThreadMain) forKey:@"ThreadMain"];
    [_HGThreadBusNames setObject:@(ThreadIO) forKey:@"ThreadIO"];
    [_HGThreadBusNames setObject:@(ThreadNet) forKey:@"ThreadNet"];
    [_HGThreadBusNames setObject:@(ThreadDb) forKey:@"ThreadDb"];
    [_HGThreadBusNames setObject:@(ThreadWorking) forKey:@"ThreadWorking"];
    [_HGThreadBusNames setObject:@(ThreadBackground) forKey:@"ThreadBackground"];
    [_HGThreadBusNames setObject:@(ThreadLog) forKey:@"ThreadLog"];
}

/**
 * 这个方法在OC里面有个缺陷，因为OC没有包名，Java里包名+类名确定唯一的类，可以确认一个类是在系统里
 * 但是OC里面，可以随意定义一个和系统同名的类，所以如果查找继承关系通过类名来过滤，会有一点点风险；
 * 但是这个风险是可接受的，因为我们几乎不会去定义一个和系统相同的类名，这个也是靠约定；
 *
 * 并且，我对工程里现有的继承关系做了统计，50%是继承自NSObject，30%是pb结构体，继承自GPBMessage;
 * 剩下的以UIView这种类型居多，所以效率上来讲是可以接受的；
 */
- (void)initSystemClasses {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    
    [set addObject:@"NSObject"];
    [set addObject:@"NSProxy"];
    [set addObject:@"UIView"];
    [set addObject:@"UITextView"];
    [set addObject:@"UILabelView"];
    [set addObject:@"UIViewController"];
    [set addObject:@"UITableViewCell"];
    [set addObject:@"UICollectionViewCell"];
    [set addObject:@"UITableViewController"];
    [set addObject:@"UIScrollView"];
    [set addObject:@"UILabel"];
    [set addObject:@"UIControl"];
    [set addObject:@"UIButton"];
    
    _systemClasses = set;
}

- (nonnull NSSet<NSString *> *)getProperties:(nonnull Class)clazz {
    pthread_rwlock_rdlock(&_lock);
    
    NSMutableSet *propertyNames = [_clazzProperties objectForKey:clazz];
    
    if (propertyNames) {
        pthread_rwlock_unlock(&_lock);
        return propertyNames;
    }
    
    pthread_rwlock_unlock(&_lock);
    pthread_rwlock_wrlock(&_lock);
    
    propertyNames = [_clazzProperties objectForKey:clazz];
    
    if (propertyNames) {
        pthread_rwlock_unlock(&_lock);
        return propertyNames;
    }
    
    unsigned int propertyCount;
    objc_property_t *props = class_copyPropertyList(clazz, &propertyCount);
    
    propertyNames = [NSMutableSet setWithCapacity:propertyCount];
    
    for (int i = 0; i < propertyCount; ++i) {
        [propertyNames addObject:[NSString stringWithUTF8String:property_getName(props[i])]];
    }
    
    free(props);
    
    [_clazzProperties setObject:propertyNames forKey:clazz];
    
    pthread_rwlock_unlock(&_lock);
    
    return propertyNames;
}

- (nonnull NSArray *)getSelectors:(nonnull NSObject *)receiver
                      sourceClass:(nonnull Class)sourceClass {
    Class receiverClass = [receiver class];
    
    NSString *key = [NSString stringWithFormat:@"%@.%@", receiverClass, sourceClass];
    
    pthread_rwlock_rdlock(&_selectorLock);
    
    NSMutableArray *selectors = [_clazzSelectors objectForKey:key];
    
    if (selectors) {
        pthread_rwlock_unlock(&_selectorLock);
        return selectors;
    }
    
    pthread_rwlock_unlock(&_selectorLock);
    
    NSSet<NSString *> *propertyNames = [self getProperties:sourceClass];
    
    pthread_rwlock_wrlock(&_selectorLock);
    
    selectors = [_clazzSelectors objectForKey:key];
    
    if (selectors) {
        pthread_rwlock_unlock(&_selectorLock);
        return selectors;
    }
    
    selectors = [NSMutableArray array];
    
    NSArray<NSValue *> *allSelectors = [self getReceiverClassMethods:receiverClass];
    
    NSMutableSet *sameNameSelectorFilter = [NSMutableSet set];
    
    for (NSUInteger i = 0; i < allSelectors.count; ++i) {
        SEL pSelector = allSelectors[i].pointerValue;
        
        NSString *selectorName = NSStringFromSelector(pSelector);
        
        //这里没有用正则表达式，因为如果类名或者属性名也有下划线时，正则表达式不好处理
        if (selectorName.length < 9 || ![selectorName hasPrefix:@"on_"] || ![selectorName hasSuffix:@":"]) {
            continue;
        }
        
        if ([sameNameSelectorFilter containsObject:selectorName]) {
            //如果子类有覆盖父类的方法，放弃父类的方法
            //OC里面，同名方法覆盖，是不看方法参数的，这里的方法参数要注意
            continue;
        }
        
        [sameNameSelectorFilter addObject:selectorName];
        
        NSString *splitName = [selectorName substringWithRange:NSMakeRange(3, selectorName.length - 4)];

        NSString *sourceClassName = NSStringFromClass(sourceClass);
        
        if (![splitName hasPrefix:sourceClassName]) {
            continue;
        }
        
        NSRange queueRange = [splitName rangeOfString:@"_" options:NSBackwardsSearch];

        if (queueRange.location == NSNotFound) {
            continue;
        }

        NSNumber *queue = [_HGThreadBusNames objectForKey:[splitName substringFromIndex:queueRange.location + 1]];

        if (!queue) {
            continue;
        }
        
        NSString *keyPath = [splitName substringWithRange:NSMakeRange(sourceClassName.length + 1,
                queueRange.location - sourceClassName.length - 1)];
        
        if (![propertyNames containsObject:keyPath]) {
            HGLogError(LogTag, @"source class does not has property: %@,"
                       " souceClass: %@, receiverClass: %@", keyPath, sourceClass, receiverClass);
#ifdef ENTERPRISE_VERSION
            [NSException raise:NSInvalidArgumentException format:@"source class does not has property: %@,"
             " souceClass: %@, receiverClass: %@", keyPath, sourceClass, receiverClass];
#endif
            continue;
        }
        
        KvoMethodNode *node = [[KvoMethodNode alloc] init];
        
        node.keyPath = keyPath;
        node.pSelector = pSelector;
        node.queue = (HGThreadTag) queue.unsignedLongLongValue;
        
        [selectors addObject:node];
    }
    
    [_clazzSelectors setObject:selectors forKey:key];
    
    pthread_rwlock_unlock(&_selectorLock);
    
    return selectors;
}

- (nonnull NSArray<NSValue *> *)getReceiverClassMethods:(nonnull Class)cls {
    NSMutableArray *selectorList = [NSMutableArray array];
    
    Class retriveClass = cls;
    
    int level = 0;
    
    while (true) {
        if ([self canClassBeFiltered:retriveClass]) {
            return selectorList;
        }
        
        //继承层级限制，如果大于5层还没有到系统里的类的话，在debug环境下就抛出异常
        if (level >= 5) {
            HGLogError(LogTag, @"too much level when search methods: %d, receiverClass: %@", level, cls);
#ifdef ENTERPRISE_VERSION
            [NSException raise:NSRangeException format:@"too much level when search methods: %d, receiverClass: %@", level, cls];
#endif
            return selectorList;
        }
        
        //数量限制，如果多于80也是有异常的
        if (selectorList.count >= 80) {
            HGLogError(LogTag, @"too much selectors in class, selector count: %d, receiverClass: %@",
                       selectorList.count, cls);
#ifdef ENTERPRISE_VERSION
            [NSException raise:NSRangeException format:@"too much selectors in class, selector count: %d, receiverClass: %@",
             selectorList.count, cls];
#endif
            return selectorList;
        }
        
        unsigned int methodCount;
        //这个只会返回实例方法，不会返回类方法
        Method *methods = class_copyMethodList(retriveClass, &methodCount);
        
        for (int i = 0; i < methodCount; ++i) {
            Method method = methods[i];
            
            [selectorList addObject:[NSValue valueWithPointer:method_getName(method)]];
        }
        
        free(methods);
        
        retriveClass = class_getSuperclass(retriveClass);
        
        level++;
    }
}

- (BOOL)canClassBeFiltered:(nonnull Class)cls {
    NSString *name = NSStringFromClass(cls);
    
    if (!name || name.length == 0 || [_systemClasses containsObject:name]) {
        return YES;
    }
    
    return NO;
}

- (void)dealloc {
    pthread_rwlock_destroy(&_lock);
    pthread_rwlock_destroy(&_selectorLock);
}

+ (nonnull NSArray *)receiverSelectorList:(nonnull NSObject *)receiver
                              sourceClass:(nonnull Class)sourceClass {
    return [[KvoHelper sharedInstance] getSelectors:receiver sourceClass:sourceClass];
}

@end
