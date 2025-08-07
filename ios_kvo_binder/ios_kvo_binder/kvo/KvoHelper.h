//
// 自动绑定的辅助类
//
#import <Foundation/Foundation.h>

@interface KvoMethodNode : NSObject

@property(nonatomic, nonnull) NSString *keyPath;

@property(nonatomic, nonnull) SEL pSelector;

@property(nonatomic) HGThreadTag queue;

@end

@interface KvoHelper : NSObject

+ (nonnull NSArray *)receiverSelectorList:(nonnull NSObject *)receiver
                              sourceClass:(nonnull Class)sourceClass;

@end
