//
//  GPUImageStillCamera+CaptureOrientation.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <GPUImage/GPUImage.h>

@interface GPUImageStillCamera (CaptureOrientation)

- (void)captureFixFlipPhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block;

- (void)captureFixFlipPhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block;

@end
