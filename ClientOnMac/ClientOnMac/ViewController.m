//
//  ViewController.m
//  ClientOnMac
//
//  Created by 宋旭 on 16/6/15.
//  Copyright © 2016年 sky. All rights reserved.
//

#import "ViewController.h"
#import "GCDAsyncSocket.h"
#import "FetchIPAddress.h"

#warning 本客户端的 昵称 和 个人消息内容 可以在这里更改
#define PERSONAL_MESSAGE @"😢钱包那么小,哪也去不了"
#define NICKNAME_LOCALHOST @"小白"
//#define HEARTBEAT_CONTENT @"HeartBeat"
//#define REPLY_HEARTBEAT @"Received"

/**
 *  服务器端socket端口号,自行设置
 */
static uint16_t serverSocket_Port = 5288;

@interface ViewController () <NSTableViewDataSource, NSTableViewDelegate, GCDAsyncSocketDelegate>

@property (weak) IBOutlet NSTextField *inputField;

- (IBAction)broadcast:(NSButton *)sender;

@property (weak) IBOutlet NSTextField *receivedBroadcstMessage;
/** 收到的个人消息 */
@property (weak) IBOutlet NSTextField *receivedMessage;
/** 发出的个人消息 */
@property (weak) IBOutlet NSTextField *messageYouSent;

/** 服务器端socket */
@property (nonatomic, strong) GCDAsyncSocket *socket;
/** 昵称列表数据源 */
@property (nonatomic, strong) NSMutableArray *dataSource;

@property (nonatomic ,strong) NSTableView *buddyList;

@property (nonatomic,strong) dispatch_queue_t globalQueue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self socketConnnectToHost];
    /** 设置容器视图、滚动条，并将表格添加到窗口中 */
    NSScrollView *tableContainer = [[NSScrollView alloc] initWithFrame:NSMakeRect(15, 20, 100, 170)];
    [tableContainer setDocumentView:self.buddyList];
    [tableContainer setHasVerticalScroller:NO];
    [tableContainer setHasHorizontalScroller:NO];
    [self.view addSubview:tableContainer];
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
 *  初始化表格视图
 *
 *  @return
 */
- (NSTableView *)setupTableView {
    
    NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 170)];
    //设置水平，坚直线
    [tableView setGridStyleMask:NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask];
    //线条色
    [tableView setGridColor:[NSColor whiteColor]];
    //设置背景色
    [tableView setBackgroundColor:[NSColor clearColor]];
    //设置每个cell的换行模式，显不下时用...
    [[tableView cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[tableView cell] setTruncatesLastVisibleLine:YES];
    [tableView sizeLastColumnToFit];
    [tableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    //设置允许多选
    [tableView setAllowsMultipleSelection:NO];
    
    [tableView setAllowsExpansionToolTips:YES];
    [tableView setAllowsEmptySelection:YES];
    [tableView setAllowsColumnSelection:YES];
    [tableView setAllowsColumnResizing:YES];
    [tableView setAllowsColumnReordering:YES];
    //双击调用方法
    [tableView setDoubleAction:@selector(onTableViewRowDoubleClicked:)];
    //显示背景色
    [tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    /** 为表格创建列 */
    NSTableColumn *column1 = [[NSTableColumn alloc] initWithIdentifier:@"col1"];
    [column1.headerCell setTitle:@"在线好友列表"];
    [column1 setWidth:150];
    /** 设置数据源和代理、添加列 */
    [tableView addTableColumn:column1];
    [tableView setDelegate:self];
    [tableView setDataSource:self];
    
    return tableView;
}

/**
 *  双击好友昵称
 *
 *  @param sender
 */
- (void)onTableViewRowDoubleClicked:(id)sender {
    
    NSInteger rowNumber = [self.buddyList clickedRow];
    
    if ([self.dataSource[rowNumber] isEqualToString:NICKNAME_LOCALHOST]) {
        NSLog(@"暂不支持给自己发消息的功能");
        
    } else if (rowNumber <= self.dataSource.count - 1) {
        
        /** 将个人消息及发送对象在好友列表中的行号打包 */
        NSString *num = [NSString stringWithFormat:@"%ld",rowNumber];
        NSDictionary *dict = @{@"PersonalMessage":PERSONAL_MESSAGE, @"toUser":num};
        NSData *messageData = [NSJSONSerialization dataWithJSONObject:dict
                                                              options:NSJSONWritingPrettyPrinted
                                                                error:nil];
        [self.socket writeData:messageData withTimeout:-1 tag:0];
        self.messageYouSent.stringValue = PERSONAL_MESSAGE;
        // 发送完个人消息，继续监听数据
        [self.socket readDataWithTimeout:-1 tag:0];
    }
}

/**
 *  点击按钮发送用户在左侧输入的广播消息
 *
 *  @param sender
 */
- (IBAction)broadcast:(NSButton *)sender {
    
    /** 若输入 exit 本客户端将下线 并将广播下线消息 */
    if (0 < self.inputField.stringValue.length) {
        
        /** 发广播消息带上昵称 */
        NSString *header = [NICKNAME_LOCALHOST stringByAppendingString:@":"];
        NSString *message = [header stringByAppendingString:self.inputField.stringValue];
        [self writeDataToSocket:self.socket withMessage:message tag:0];
        
        /** 下线流程本地要执行的操作:移除在线好友列表中的数据 */
        if ([self.inputField.stringValue isEqualToString:@"exit"]) {
            [self.dataSource removeAllObjects];
            /** 刷新列表 */
            [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
                self.messageYouSent.stringValue = @"";
                self.receivedMessage.stringValue = @"";
                self.receivedBroadcstMessage.stringValue = @"";
                self.inputField.stringValue = @"";
                [self.buddyList reloadData];
            }];
        }
    } else {
        assert("不能广播空消息");
    }
}

#pragma mark - NSTableView Delegate & DataSource Methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.dataSource.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    
    return [self.dataSource objectAtIndex:row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    
    NSString *nickName = [self.dataSource objectAtIndex:row];
    
    [nickName setValue:object forKey:[tableColumn identifier]];
}

- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if ([tableColumn.identifier isEqualToString:@"col1"]) {
        NSCell *cell = [[NSCell alloc] init];
        
        cell.title = [self.dataSource objectAtIndex:row];
        return cell;
    }
    return nil;
}

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
            self.receivedMessage.stringValue = message;
        } else {
            /** 读取并显示广播内容 */
            NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
                self.receivedBroadcstMessage.stringValue = dataStr;
            }];
        }
    }
    // 每次接收完数据，都要再次监听数据
    [self.socket readDataWithTimeout:-1 tag:0];
}

#pragma mark Socket Delegate Methods
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"连接主机成功");
    //发送昵称
    [self writeDataToSocket:self.socket withMessage:NICKNAME_LOCALHOST tag:50];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"连接已断开 %@",err);
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (50 == tag) {
        NSLog(@"昵称发送成功");
    } else {
        NSLog(@"消息发送成功..");
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

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}

#pragma mark - Getters
- (NSMutableArray *)dataSource {
    if (!_dataSource) {
        _dataSource = [NSMutableArray array];
    }
    return _dataSource;
}

- (NSTableView *)buddyList {
    if (!_buddyList) {
        _buddyList = [self setupTableView];
    }
    return _buddyList;
}

- (dispatch_queue_t)globalQueue {
    if (!_globalQueue) {
        _globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    }
    return _globalQueue;
}

@end
