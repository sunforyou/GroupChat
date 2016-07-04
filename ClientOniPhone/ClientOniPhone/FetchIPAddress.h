//
//  FetchIPAddress.h
//  FetchIPAddress
//
//  Created by 宋旭 on 16/7/1.
//  Copyright © 2016年 sky. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FetchIPAddress : NSObject

+ (instancetype)sharedInstance;

/**
 *  获取本地ip地址
 *
 *  @return <#return value description#>
 */
- (NSString *)getIpAddresses;

@end
