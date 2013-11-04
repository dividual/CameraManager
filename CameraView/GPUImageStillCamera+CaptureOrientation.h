//
//  GPUImageStillCamera+CaptureOrientation.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "GPUImageStillCamera.h"
#import "GPUImage.h"

@interface GPUImageStillCamera (CaptureOrientation)

- (void)captureFixFlipPhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block;

@end
