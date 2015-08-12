//
//  GetuiDelegate.m
//  GetuiPushNotification
//
//  Created by jiong.li on 14/11/28.
//
//

#import "GetuiDelegateImpl.h"

#define NotifyActionKey "NotifyAction"
NSString* const NotificationCategoryIdent  = @"ACTIONABLE";
NSString* const NotificationActionOneIdent = @"ACTION_ONE";
NSString* const NotificationActionTwoIdent = @"ACTION_TWO";

@implementation GetuiDelegateImpl

@synthesize freContext = _freContext;
@synthesize appKey = _appKey;
@synthesize appSecret = _appSecret;
@synthesize appID = _appID;
@synthesize clientId = _clientId;
@synthesize sdkStatus = _sdkStatus;
@synthesize lastPayloadIndex = _lastPaylodIndex;
@synthesize payloadId = _payloadId;

-(void)dealloc
{
    [_deviceToken release];
    [_appKey release];
    [_appSecret release];
    [_appID release];
    [_clientId release];
    [_payloadId release];
    
    [super dealloc];
}


// 注册消息推送
- (void)registerRemoteNotification
{
#ifdef __IPHONE_8_0
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        //IOS8 新的通知机制category注册
        UIMutableUserNotificationAction *action1;
        action1 = [[UIMutableUserNotificationAction alloc] init];
        [action1 setActivationMode:UIUserNotificationActivationModeBackground];
        [action1 setTitle:@"取消"];
        [action1 setIdentifier:NotificationActionOneIdent];
        [action1 setDestructive:NO];
        [action1 setAuthenticationRequired:NO];
        
        UIMutableUserNotificationAction *action2;
        action2 = [[UIMutableUserNotificationAction alloc] init];
        [action2 setActivationMode:UIUserNotificationActivationModeBackground];
        [action2 setTitle:@"回复"];
        [action2 setIdentifier:NotificationActionTwoIdent];
        [action2 setDestructive:NO];
        [action2 setAuthenticationRequired:NO];
        
        UIMutableUserNotificationCategory *actionCategory;
        actionCategory = [[UIMutableUserNotificationCategory alloc] init];
        [actionCategory setIdentifier:NotificationCategoryIdent];
        [actionCategory setActions:@[action1, action2]
                        forContext:UIUserNotificationActionContextDefault];
        
        NSSet *categories = [NSSet setWithObject:actionCategory];
        UIUserNotificationType types = (UIUserNotificationTypeAlert|
                                        UIUserNotificationTypeSound|
                                        UIUserNotificationTypeBadge);
        
        UIUserNotificationSettings *settings;
        settings = [UIUserNotificationSettings settingsForTypes:types categories:categories];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        
        [action1 release];
        [action2 release];
        [actionCategory release];
        
    } else {
        UIRemoteNotificationType apn_type = (UIRemoteNotificationType)(UIRemoteNotificationTypeAlert|
                                                                       UIRemoteNotificationTypeSound|
                                                                       UIRemoteNotificationTypeBadge);
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes:apn_type];
    }
#else
    UIRemoteNotificationType apn_type = (UIRemoteNotificationType)(UIRemoteNotificationTypeAlert|
                                                                   UIRemoteNotificationTypeSound|
                                                                   UIRemoteNotificationTypeBadge);
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:apn_type];
#endif
}

-(void) stopSdk {
    [GeTuiSdk enterBackground];
}

- (void) enterBackground {
    // [EXT] APP进入后台时，通知个推SDK进入后台
    [GeTuiSdk enterBackground];
}

- (void) recoverFromBackground {
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    
    // [EXT] 重新上线
    [self startSdkWith:_appID appKey:_appKey appSecret:_appSecret];
}


//#pragma mark - background fetch  唤醒
//- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
//    
//    //[5] Background Fetch 恢复SDK 运行
//    [GeTuiSdk resume];
//    completionHandler(UIBackgroundFetchResultNewData);
//}

// 注册成功
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
    NSString *token = [[deviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    [_deviceToken release];
    _deviceToken = [[token stringByReplacingOccurrencesOfString:@" " withString:@""] retain];
   
    if ( _freContext != nil )
    {
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"TOKEN_SUCCESS", (uint8_t*)[_deviceToken UTF8String]);
    }
    
    // [3]:向个推服务器注册deviceToken
    [GeTuiSdk registerDeviceToken:_deviceToken];
}

//注册失败
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
    
    NSString* tokenString = [NSString stringWithFormat:@"Failed to get token, error: %@",error];
    
    if ( _freContext != nil )
    {
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"TOKEN_FAIL", (uint8_t*)[tokenString UTF8String]);
    }
    
    // [3-EXT]:如果APNS注册失败，通知个推服务器
    [GeTuiSdk registerDeviceToken:@""];
}

- (void)didReceiveRemoteNotification:(NSDictionary *)userinfo
{
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    
    // [4-EXT]:处理APN
    NSString *stringInfo = [GetuiDelegateImpl convertToJSonString:userinfo];
    if ( _freContext != nil )
    {
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"RECEIVE_REMOTE_NOTIFICATION", (uint8_t*)[stringInfo UTF8String]);
    }
}

- (void)startSdkWith:(NSString *)appID appKey:(NSString *)appKey appSecret:(NSString *)appSecret
{
    _appID = [appID retain];
    _appKey = [appKey retain];
    _appSecret = [appSecret retain];
    
    NSError *err = nil;
    
    //[1-1]:通过 AppId、 appKey 、appSecret 启动SDK
    [GeTuiSdk startSdkWithAppId:appID appKey:appKey appSecret:appSecret delegate:self error:&err];
    
    //[1-2]:设置是否后台运行开关
    [GeTuiSdk runBackgroundEnable:NO];
    
    //[1-3]:设置电子围栏功能，开启LBS定位服务 和 是否允许SDK 弹出用户定位请求
    [GeTuiSdk lbsLocationEnable:NO andUserVerify:NO];
    
    if(err &&  _freContext != nil) {
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"start_getui_sdk_error", (uint8_t*)[[err localizedDescription] UTF8String]);
    }
    
}

- (void)setDeviceToken:(NSString *)aToken
{
    [GeTuiSdk registerDeviceToken:aToken];
}

- (BOOL)setTags:(NSArray *)aTags error:(NSError **)error
{
    return [GeTuiSdk setTags:aTags];
}

- (NSString *)sendMessage:(NSData *)body error:(NSError **)error
{
    return [GeTuiSdk sendMessage:body error:error];
}

- (void)bindAlias:(NSString *)aAlias {
    [GeTuiSdk bindAlias:aAlias];
}

- (void)unbindAlias:(NSString *)aAlias {
    
    [GeTuiSdk unbindAlias:aAlias];
}

#pragma mark - GexinSdkDelegate
- (void)GeTuiSdkDidRegisterClient:(NSString *)clientId
{
    // [4-EXT-1]: 个推SDK已注册，返回clientId
    [_clientId release];
    _clientId = [clientId retain];
    if (_deviceToken) {
        [GeTuiSdk registerDeviceToken:_deviceToken];
    }
    if ( _freContext != nil )
    {
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"GETUI_DID_REGISTER_CLIENT", (uint8_t*)[_clientId UTF8String]);
    }
}

- (void)GeTuiSdkDidReceivePayload:(NSString *)payloadId andTaskId:(NSString *)taskId andMessageId:(NSString *)aMsgId fromApplication:(NSString *)appId
{
    // [4]: 收到个推消息
    [_payloadId release];
    _payloadId = [payloadId retain];
    
    NSData* payload = [GeTuiSdk retrivePayloadById:payloadId];
    NSString *payloadMsg = nil;
    if (payload) {
        payloadMsg = [[NSString alloc] initWithBytes:payload.bytes
                                              length:payload.length
                                            encoding:NSUTF8StringEncoding];
        if ( _freContext != nil )
        {
            NSString *record = [NSString stringWithFormat:@"%d, %@, %@", ++_lastPaylodIndex, [self formateTime:[NSDate date]], payloadMsg];
            FREDispatchStatusEventAsync(_freContext, (uint8_t*)"GETUI_DID_RECEIVE_PAYLOAD", (uint8_t*)[record UTF8String]);
        }
    }
    [payloadMsg release];
}

- (void)GeTuiSdkDidSendMessage:(NSString *)messageId result:(int)result {
    // [4-EXT]:发送上行消息结果反馈
//    NSString *record = [NSString stringWithFormat:@"Received sendmessage:%@ result:%d", messageId, result];
}

- (void)GeTuiSdkDidOccurError:(NSError *)error
{
    // [EXT]:个推错误报告，集成步骤发生的任何错误都在这里通知，如果集成后，无法正常收到消息，查看这里的通知。
    if ( _freContext != nil )
    {
        NSString *logMsg = [NSString stringWithFormat:@">>>[GeTuiSdk error]:%@", [error localizedDescription]];
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"GETUI_DID_OCCUR_ERROR", (uint8_t*)[logMsg UTF8String]);
    }
}

- (void)GeTuiSDkDidNotifySdkState:(SdkStatus)aStatus {
    // [EXT]:通知SDK运行状态
    _sdkStatus = aStatus;
}

//SDK设置推送模式回调
- (void)GeTuiSdkDidSetPushMode:(BOOL)isModeOff error:(NSError *)error {
    NSString *logMsg;
    if (error) {
        logMsg = [NSString stringWithFormat:@">>>[SetModeOff error]: %@", [error localizedDescription]];
    }else{
        logMsg = [NSString stringWithFormat:@">>>[GexinSdkSetModeOff]: %@",isModeOff?@"开启":@"关闭"];
    }
    if(_freContext != nil)
    {
        FREDispatchStatusEventAsync(_freContext, (uint8_t*)"GETUI_SET_PUSH_MODE_INFO", (uint8_t*)[logMsg UTF8String]);
    }
    
}

-(NSString*) formateTime:(NSDate*) date {
    NSDateFormatter* formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString* dateTime = [formatter stringFromDate:date];
    [formatter release];
    return dateTime;
}

+ (NSString*)convertToJSonString:(NSDictionary*)dict
{
    if(dict == nil) {
        return @"{}";
    }
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&jsonError];
    if (jsonError != nil) {
        NSLog(@"[AirPushNotification] JSON stringify error: %@", jsonError.localizedDescription);
        return @"{}";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}


@end

