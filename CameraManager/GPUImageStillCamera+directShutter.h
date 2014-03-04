//
//  GPUImageStillCamera+directShutter.h
//  CameraManagerExample
//
//  Created by Shinya Matsuyama on 3/4/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import "GPUImageStillCamera.h"

@interface GPUImageStillCamera (directShutter)

@property (readonly, nonatomic) AVCaptureStillImageOutput *stillImageOutput;

- (void)captureDirectWithOrientation:(UIDeviceOrientation)orientation completion:(void(^)(UIImage *image, NSError *error))completion;

@end
