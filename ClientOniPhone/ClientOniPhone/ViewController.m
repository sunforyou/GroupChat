//
//  ViewController.m
//  ClientOniPhone
//
//  Created by 宋旭 on 16/6/16.
//  Copyright © 2016年 sky. All rights reserved.
//

#import "ViewController.h"
#import "GCDAsyncSocket.h"
#import "FetchIPAddress.h"

#warning 本客户端的 昵称 和 个人消息内容 可以在这里更改
#define PERSONAL_MESSAGE  @"😊世界那么大,赶紧去看看"
#define NICKNAME_LOCALHOST @"韦恩"

/**
 *  服务器端socket端口号,自行设置
 */
static uint16_t serverSocket_Port = 5288;

@interface ViewController () <UITableViewDelegate, UITableViewDataSource, GCDAsyncSocketDelegate>

@property (weak, nonatomic) IBOutlet UILabel *receivedBroadCastMessage;

@property (weak, nonatomic) IBOutlet UITextField *inputSthNeedBroadCast;

@property (weak, nonatomic) IBOutlet UITableView *buddyList;

- (IBAction)sendBroadCastMessage:(UIButton *)sender;

@property (weak, nonatomic) IBOutlet UILabel *receivedMessage;

@property (weak, nonatomic) IBOutlet UILabel *messageSended;

@property (nonatomic, strong) GCDAsyncSocket *socket;
/** 数据源 */
@property (nonatomic, strong) NSMutableArray *dataSource;

@property (nonatomic,strong) dispatch_queue_t globalQueue;

@end

@implementation ViewController

- (NSMutableArray *)dataSource {
    if (!_dataSource) {
        _dataSource = [NSMutableArray array];
    }
    return _dataSource;
}

- (dispatch_queue_t)globalQueue {
    if (!_globalQueue) {
        _globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    }
    return _globalQueue;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self socketConnnectToHost];
    /** 设定Label可换行 */
    self.receivedBroadCastMessage.numberOfLines = 0;
    self.receivedMessage.numberOfLines = 0;
    self.messageSended.numberOfLines = 0;
}

/**
 *  连接服务器
 */
- (void)socketConnnectToHost {
    // 连接到聊天服务器
    GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                        delegateQueue:self.globalQueue];
    
    NSString *serverSocket_IP = [[FetchIPAddress sharedInstance] getIpAddresses];
    [socket connectToHost:serverSocket_IP onPort:serverSocket_Port error:nil];
    self.socket = socket;
    NSLog(@"%@",serverSocket_IP);
}

/**
 *  发送广播消息
 *
 *  @param sender
 */
- (IBAction)sendBroadCastMessage:(UIButton *)sender {
    
    /** 若输入 exit 本客户端将下线 并将广播下线消息 */
    if (self.inputSthNeedBroadCast.text.length > 0) {
        
        /** 发广播消息带上昵称 */
        NSString *header = [NICKNAME_LOCALHOST stringByAppendingString:@":"];
        NSString *message = [header stringByAppendingString:self.inputSthNeedBroadCast.text];
        [self writeDataToSocket:self.socket withMessage:message tag:0];
        
        /** 下线流程本地要执行的操作:移除在线好友列表中的数据 */
        if ([self.inputSthNeedBroadCast.text isEqualToString:@"exit"]) {
            [self.dataSource removeAllObjects];
            /** 刷新列表 */
            [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
                //清空页面信息,并回收键盘
                self.messageSended.text = @"";
                self.receivedMessage.text = @"";
                self.receivedBroadCastMessage.text = @"";
                [self.inputSthNeedBroadCast setText:@""];
                [self.inputSthNeedBroadCast resignFirstResponder];
                [self.buddyList reloadData];
            }];
        }
    } else {
        assert("不能广播空消息");
    }
}

#pragma mark - TableView Delegate & DataSource Methods
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseID = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    
    cell.textLabel.text = self.dataSource[indexPath.row];
    cell.textLabel.numberOfLines = 0;
    return cell;
}

/** 单击Cell自动发送个人消息 */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if ([self.dataSource[indexPath.row] isEqualToString:NICKNAME_LOCALHOST]) {
        NSLog(@"暂不支持给自己发消息的功能");
    } else if (indexPath.row <= self.dataSource.count - 1) {
        /** 将个人消息及发送对象在好友列表中的行号打包 */
        NSString *num = [NSString stringWithFormat:@"%ld",indexPath.row];
        NSDictionary *dict = @{@"PersonalMessage":PERSONAL_MESSAGE, @"toUser":num};
        NSData *messageData = [NSJSONSerialization dataWithJSONObject:dict
                                                              options:NSJSONWritingPrettyPrinted
                                                                error:nil];
        [self.socket writeData:messageData withTimeout:-1 tag:0];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            self.messageSended.text = PERSONAL_MESSAGE;
        }];
        // 发送完个人消息，继续监听数据
        [self.socket readDataWithTimeout:-1 tag:0];
    }
}

#pragma mark - Tool Methods
/**
 *  自定义数据发送
 */
- (void)writeDataToSocket:(GCDAsyncSocket *)socket withMessage:(NSString *)str tag:(long)tag {
    [socket writeData:[str dataUsingEncoding:NSUTF8StringEncoding]
          withTimeout:-1
                  tag:tag];
    
    // 监听数据
    [socket readDataWithTimeout:-1 tag:0];
}

#pragma mark - GCDAsyncSocket Delegate Methods
/**
 *  读取来自服务器的数据
 *
 *  @param sock
 *  @param data
 *  @param tag
 */
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
    /** 读取广播数据 */
    NSKeyedUnarchiver *unArchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    
    if ([unArchiver containsValueForKey:@"NickLists"]) {
        NSArray *nickNamesArray = [unArchiver decodeObjectForKey:@"NickLists"];
        /** 清空旧数据,填入新数据 */
        [self.dataSource removeAllObjects];
        [self.dataSource addObjectsFromArray:nickNamesArray];
        
        /** 刷新列表 */
        [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
            [self.buddyList reloadData];
        }];
        
    } else {
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                                             options:NSJSONReadingMutableContainers
                                                               error:nil];
        //区分消息类型:个人消息、广播消息
        if ([dict objectForKey:@"PersonalMessage"]) {
            
            NSString *header = [[dict objectForKey:@"FromUser"] stringByAppendingString:@":"];
            NSString *message = [header stringByAppendingString:[dict objectForKey:@"PersonalMessage"]];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.receivedMessage.text = message;
            }];
            
        } else {
            /** 读取并显示广播内容 */
            NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.receivedBroadCastMessage.text = dataStr;
            }];
        }
    }
    // 每次接收完数据，都要再次监听数据
    [self.socket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"连接主机成功");
    //发送昵称
    [self writeDataToSocket:self.socket withMessage:NICKNAME_LOCALHOST tag:50];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (50 == tag) {
        NSLog(@"昵称发送成功");
    } else {
        NSLog(@"消息发送成功..");
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"连接已断开 %@",err);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.inputSthNeedBroadCast resignFirstResponder];
    [self.inputSthNeedBroadCast setText:@""];
}

@end
