//
//  main.m
//  ServerOnMac
//
//  Created by 宋旭 on 16/6/19.
//  Copyright © 2016年 sky. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ServerListener.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 1.创建服务监听器
        ServerListener *listener = [[ServerListener alloc] init];
        
        // 2.开始监听
        [listener startListening];
        
        // 开启主运行循环
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
