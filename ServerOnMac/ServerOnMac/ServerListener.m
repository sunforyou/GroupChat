//
//  ServerListener.m
//  ServerOnMac
//
//  Created by 宋旭 on 16/6/19.
//  Copyright © 2016年 sky. All rights reserved.
//

#import "ServerListener.h"
#import "GCDAsyncSocket.h"

#define NICKLIST_FILEPATH   [NSHomeDirectory() stringByAppendingPathComponent:@"nicklist.log"]
#define SERVERLOG_FILEPATH  [NSHomeDirectory() stringByAppendingPathComponent:@"server.log"]
#define HEARTBEAT_CONTENT @"HeartBeat"
#define REPLY_HEARTBEAT @"Received"

@interface ServerListener() <GCDAsyncSocketDelegate>

/**
 * 服务端Socket
 */
@property (nonatomic, strong) GCDAsyncSocket *serverSocket;

/*
 * 所有的客户端
 */
@property (nonatomic, strong) NSMutableArray *clientSockets;

/**
 *  服务器日志
 */
@property (nonatomic, strong) NSMutableString *log;//日志

/**
 *  在线用户昵称列表
 */
@property (nonatomic, strong) NSMutableDictionary *nickNameLists;

/**
 *  心跳连接定时器
 */
@property (nonatomic, strong) NSTimer *connectTimer;

@end

@implementation ServerListener

- (NSMutableString *)log {
    if (!_log) {
        _log = [NSMutableString string];
    }
    return _log;
}

- (NSMutableArray *)clientSockets {
    if (!_clientSockets) {
        _clientSockets = [NSMutableArray array];
    }
    return _clientSockets;
}

- (NSMutableDictionary *)nickNameLists {
    if (!_nickNameLists) {
        _nickNameLists = [NSMutableDictionary dictionary];
    }
    return _nickNameLists;
}

- (instancetype)init {
    if (self = [super init]) {
        self.serverSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    }
    return self;
}

- (void)startListening {
    NSError *error = nil;
    BOOL success = [self.serverSocket acceptOnPort:5288 error:&error];
    if (success) {
        NSLog(@"5288端口开启成功,正在监听客户端连接请求...");
    }else{
        NSLog(@"5288端口开启失败...");
    }
}

#pragma mark -代理
- (void)socket:(GCDAsyncSocket *)serverSocket didAcceptNewSocket:(GCDAsyncSocket *)clientSocket {
    
    NSLog(@"发现客户端 %@ IP: %@: %zd 请求连接...",clientSocket,clientSocket.connectedHost,clientSocket.connectedPort);
    // 1.将客户端socket保存起来
    [self.clientSockets addObject:clientSocket];
    
    // 2.一旦同意连接，监听数据读取，如果有数据会调用下面的代理方法
    [clientSocket readDataWithTimeout:-1 tag:100];
    
    NSLog(@"当前在线用户个数:%ld",self.clientSockets.count);
}

/**
 *  读取客户端传来的数据
 *
 *  @param clientSocket
 *  @param data
 *  @param tag
 */
- (void)socket:(GCDAsyncSocket *)clientSocket didReadData:(NSData *)data withTag:(long)tag {
    
    /** 将客户端传来的数据转成字符串 */
    NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    if (100 == tag) {
        /** 记录接收到的昵称和客户端地址 */
        NSString *port = [NSString stringWithFormat:@"%zd", clientSocket.connectedPort];
        [self.nickNameLists setValue:message forKey:port];
        
        /** 好友上线广播内容 */
        NSString *onlineStr = [NSString stringWithFormat:@"%@骑着高头大马上线了,快来膜拜!",[self fetchNickNameOfSocket:clientSocket]];
        
        /** 检测当前聊天室是否多于一人在线 */
        if (1 <= self.clientSockets.count) {
            
            /** 好友上线消息广播给除本人以外所有在线的人 */
            for (GCDAsyncSocket *socket in self.clientSockets) {
                if (![socket isEqual:clientSocket]) {
                    [self writeDataWithSocket:socket str:onlineStr];
                }
                /** 服务器发送给刚连接的客户端一份在线好友的列表 */
                [self sendNickNameListToBuddyOnLineWithSocket:socket];
            }
        }
        // 继续监听数据读取
        [clientSocket readDataWithTimeout:-1 tag:0];
        return;
    }
    
    if ([message isEqualToString:HEARTBEAT_CONTENT]) {
        /** 收到客户端心跳包即回复 */
        [self writeDataWithSocket:clientSocket str:REPLY_HEARTBEAT WithTag:88];
        return;
    }
    
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                                         options:NSJSONReadingMutableContainers
                                                           error:nil];
    //区分接收到的消息类型:个人消息、广播消息
    if ([dict objectForKey:@"PersonalMessage"]) {
        NSInteger toUserNumber = [[dict objectForKey:@"toUser"] integerValue];
        [dict setValue:[self fetchNickNameOfSocket:clientSocket] forKey:@"FromUser"];
        
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
        
        [self.clientSockets[toUserNumber] writeData:data withTimeout:-1 tag:0];
    } else {
        /** 将客户端传入的非昵称数据存入日志 */
        if (![message containsString:@"exit"]) {
            NSString *log = [NSString stringWithFormat:@"IP:%@ %zd data:%@\n",clientSocket.connectedHost, clientSocket.connectedPort, message];
            /** 是否有必要记录日志? */
            [self.log appendString:log];
            [self.log writeToFile:SERVERLOG_FILEPATH atomically:NO encoding:NSUTF8StringEncoding error:nil];
            
            /** 广播消息 */
            for (GCDAsyncSocket *socket in self.clientSockets) {
                if (![clientSocket isEqual:socket]) {
                    [self writeDataWithSocket:socket str:message];
                }
            }
        } else {
            /** 用户输入exit模拟正常下线操作 */
            [self exitWithSocket:clientSocket];
        }
    }
    // 继续监听数据读取
    [clientSocket readDataWithTimeout:-1 tag:0];
}

/**
 *  给客户端发送好友列表
 *
 *  @param socket <#socket description#>
 */
- (void)sendNickNameListToBuddyOnLineWithSocket:(GCDAsyncSocket *)socket {
    
    NSMutableArray *nickArray = [NSMutableArray array];
    [self.nickNameLists enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop)
     {
         [nickArray addObject:(NSString *)obj];
     }];
    
    /** 创建可变data对象存储归档数据 */
    NSMutableData *data = [NSMutableData data];
    /** 创建归档对象 */
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    /** 把对象编码 */
    [archiver encodeObject:[nickArray copy] forKey:@"NickLists"];
    /** 编码完成 */
    [archiver finishEncoding];
    /** 保存归档 */
    [data writeToFile:NICKLIST_FILEPATH atomically:YES];
    NSData *message = [NSData dataWithContentsOfFile:NICKLIST_FILEPATH];
    /** 取出归档数据并上传 */
    [socket writeData:message withTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (88 == tag) {
        NSLog(@"心跳包回复报文发送成功");
    } else {
        NSLog(@"数据发送成功..");
    }
}

/**
 *  客户端下线
 *
 *  @param clientSocket
 */
- (void)exitWithSocket:(GCDAsyncSocket *)clientSocket {
    
    /** 好友下线通知内容 */
    NSString *offLineNotification = [[self fetchNickNameOfSocket:clientSocket]
                                     stringByAppendingString:@":我下线了"];
    /** 将请求下线的客户端从聊天室移除 */
    [self.clientSockets removeObject:clientSocket];
    
    /** 将下线好友移除在线好友列表 */
    NSString *port = [NSString stringWithFormat:@"%zd", clientSocket.connectedPort];
    [self.nickNameLists removeObjectForKey:port];
    
    /** 广播好友下线通知 */
    for (GCDAsyncSocket *socket in self.clientSockets) {
        if (![socket isEqual:clientSocket]) {
            [self writeDataWithSocket:socket str:offLineNotification];
            [self sendNickNameListToBuddyOnLineWithSocket:socket];
        }
    }
    NSLog(@"当前在线用户个数:%ld",self.clientSockets.count);
}

#pragma mark -私有方法
#pragma mark -写数据
/**
 *  发送消息
 *
 *  @param clientSocket
 *  @param str
 */
- (void)writeDataWithSocket:(GCDAsyncSocket *)clientSocket str:(NSString *)str {
    [clientSocket writeData:[str dataUsingEncoding:NSUTF8StringEncoding]
                withTimeout:-1
                        tag:0];
    [clientSocket readDataWithTimeout:-1 tag:0];
}

/**
 *  发送消息
 *
 *  @param clientSocket
 *  @param str
 */
- (void)writeDataWithSocket:(GCDAsyncSocket *)clientSocket str:(NSString *)str WithTag:(long)tag {
    [clientSocket writeData:[str dataUsingEncoding:NSUTF8StringEncoding]
                withTimeout:-1
                        tag:tag];
    [clientSocket readDataWithTimeout:-1 tag:tag];
}

#pragma mark - Tool Methods
/**
 *  获取客户端的昵称
 *
 *  @param clientSocket
 *
 *  @return
 */
- (NSString *)fetchNickNameOfSocket:(GCDAsyncSocket *)clientSocket {
    NSString *port = [NSString stringWithFormat:@"%zd", clientSocket.connectedPort];
    NSString *nickName = [self.nickNameLists objectForKey:port];
    return nickName;
}

@end
