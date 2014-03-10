//
//  SaveToCameraRollOperation.m
//  CameraManagerExample
//
//  Created by noughts on 2014/03/10.
//  Copyright (c) 2014年 Shinya Matsuyama. All rights reserved.
//

#import "SaveToCameraRollOperation.h"
#import <AssetsLibrary/AssetsLibrary.h>

@implementation SaveToCameraRollOperation{
	BOOL isExecuting;
	BOOL isFinished;
	NSData* _data;
}

// 監視するキー値の設定
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString*)key {
	
	if ([key isEqualToString:@"isExecuting"] || [key isEqualToString:@"isFinished"]) {
		return YES;
	}
	return [super automaticallyNotifiesObserversForKey:key];
}


-(BOOL)isConcurrent{
	return YES;
}
-(BOOL)isExecuting{
	return isExecuting;
}
-(BOOL)isFinished{
	return isFinished;
}


- (id)initWithData:(NSData*)data{
	self = [super init];
	if (self) {
		_data = data;
	}
	isExecuting = NO;
	isFinished = NO;
	return self;
}


-(void)start{
	NSLog( @"カメラロールへの保存を開始します" );
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"isExecuting"];
	ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
	[library writeImageDataToSavedPhotosAlbum:_data metadata:nil completionBlock:^(NSURL *assetURL, NSError *error){
		if(error){
			 NSLog(@"ERROR: the image failed to be written");
		 } else {
			 NSLog(@"PHOTO SAVED - assetURL: %@", assetURL);
		 }
		[self setValue:[NSNumber numberWithBool:NO] forKey:@"isExecuting"];
		[self setValue:[NSNumber numberWithBool:YES] forKey:@"isFinished"];
	 }];
}




@end
