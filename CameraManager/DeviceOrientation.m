//
//  DeviceOrientation.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "DeviceOrientation.h"
#import <CoreMotion/CoreMotion.h>

@interface DeviceOrientation ()
@property (strong, nonatomic) CMMotionManager *motionManager;
@property (assign, nonatomic) CGFloat deviceAngle;
@property (assign, nonatomic) CGFloat deviceAngleZ;
@end

@implementation DeviceOrientation

#pragma mark singleton

+ (DeviceOrientation*)sharedManager
{
    static dispatch_once_t pred = 0;
    __strong static id _sharedObject = nil;
    
    dispatch_once(&pred, ^{
        
        _sharedObject = [[DeviceOrientation alloc] init]; // or some other init method
    });
    
    return _sharedObject;
}

#pragma mark -

- (id)init
{
    self = [super init];
    if(self)
    {
        
    }
    return self;
}

#pragma mark -

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey
{
    BOOL automatic = NO;
    
    if ([theKey isEqualToString:@"orientation"])
    {
        automatic = NO;
    }
    else
    {
        automatic = [super automaticallyNotifiesObserversForKey:theKey];
    }
    return automatic;
}

- (void)updateOrientation
{
    CGFloat baseAngle = self.orientationAngle;
    
    if(_deviceAngleZ>0.98)
    {
        self.orientation = UIDeviceOrientationFaceDown;
        return;
    }
    else if(_deviceAngleZ<-0.98)
    {
        self.orientation = UIDeviceOrientationFaceUp;
        return;
    }
    
    //  別の確度に変化するときは、基準確度よりも外に多めにずれてから。対角に変化するときは、基準値に入ればそのまま。
    CGFloat dd = M_PI_4*0.2;
    
    if(((-M_PI_4+dd) < baseAngle) && (baseAngle <= (M_PI_4-dd)))
    {
        self.orientation = UIDeviceOrientationPortrait;
        return;
    }
    else if(((-3 * M_PI_4+dd) < baseAngle) && (baseAngle <= (-M_PI_4-dd)))
    {
        self.orientation = UIDeviceOrientationLandscapeLeft;
        return;
    }
    else if(((M_PI_4+dd) < baseAngle) && (baseAngle <= (3*M_PI_4-dd)))
    {
        self.orientation = UIDeviceOrientationLandscapeRight;
        return;
    }
    else if(((M_PI_4*3+dd)<baseAngle) || ((-M_PI_4*3-dd)>baseAngle))
    {
        self.orientation = UIDeviceOrientationPortraitUpsideDown;
        return;
    }
}

- (void)setOrientation:(UIDeviceOrientation)orientation
{
    if(_orientation != orientation)
    {
        [self willChangeValueForKey:@"orientation"];
        _orientation = orientation;
        [self didChangeValueForKey:@"orientation"];
    }
}

- (CGFloat)orientationAngle
{
#if TARGET_IPHONE_SIMULATOR
	switch (self.orientation)
	{
		case UIDeviceOrientationPortrait:
			return 0.0f;
		case UIDeviceOrientationPortraitUpsideDown:
			return M_PI;
		case UIDeviceOrientationLandscapeLeft:
			return -(M_PI/2.0f);
		case UIDeviceOrientationLandscapeRight:
			return (M_PI/2.0f);
		default:
			return 0.0f;
	}
#else
    return _deviceAngle;
#endif
}

- (void)startAccelerometer
{
    //  インスタンスの生成
    _motionManager = [[CMMotionManager alloc] init];
    
    if(_motionManager.accelerometerAvailable)
    {
        // センサーの更新間隔の指定
        _motionManager.accelerometerUpdateInterval = 0.1;  // 10Hz
        
        // ハンドラを指定
        CMAccelerometerHandler handler = ^(CMAccelerometerData *data, NSError *error) {
            
            CGFloat xx = data.acceleration.x;
            CGFloat yy = -data.acceleration.y;
            _deviceAngle = M_PI / 2.0f - atan2(yy, xx);
            
            _deviceAngleZ = data.acceleration.z;
            
            if(_deviceAngle > M_PI)
                _deviceAngle -= 2 * M_PI;
            
            [self updateOrientation];
        };
        
        // センサーの利用開始
        [_motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:handler];
    }
}

- (void)stopAccelerometer
{
    // (不必要になったら)センサーの停止
    if(_motionManager.accelerometerActive)
    {
        [_motionManager stopAccelerometerUpdates];
        _motionManager = nil;
    }
}

@end

