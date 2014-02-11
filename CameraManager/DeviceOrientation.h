//
//  DeviceOrientation.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DeviceOrientation : NSObject
{
    UIDeviceOrientation _orientation;
}
@property (readonly, nonatomic) UIDeviceOrientation orientation;

+ (DeviceOrientation*)sharedManager;

- (void)startAccelerometer;
- (void)stopAccelerometer;

@end
