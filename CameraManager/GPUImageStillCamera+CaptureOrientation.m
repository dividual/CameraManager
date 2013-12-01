//
//  GPUImageStillCamera+CaptureOrientation.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "GPUImageStillCamera+CaptureOrientation.h"

@interface GPUImageStillCamera (private)
- (void)capturePhotoProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withImageOnGPUHandler:(void (^)(NSError *error))block;
@end

@implementation GPUImageStillCamera (CaptureOrientation)

- (void)captureFixFlipPhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block
{
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        UIImage *filteredPhoto = nil;
        
        if(!error){
            BOOL isFlipped = self.cameraPosition == AVCaptureDevicePositionFront && self.horizontallyMirrorFrontFacingCamera?YES:NO;
            
            UIImageOrientation imageOrientation = UIImageOrientationLeft;
            switch (orientation)
            {
                case UIDeviceOrientationPortrait:
                    imageOrientation = isFlipped?UIImageOrientationUpMirrored:UIImageOrientationUp;
                    break;
                case UIDeviceOrientationPortraitUpsideDown:
                    imageOrientation = isFlipped?UIImageOrientationDownMirrored:UIImageOrientationDown;
                    break;
                case UIDeviceOrientationLandscapeLeft:
                    imageOrientation = isFlipped?UIImageOrientationRightMirrored:UIImageOrientationLeft;
                    break;
                case UIDeviceOrientationLandscapeRight:
                    imageOrientation = isFlipped?UIImageOrientationLeftMirrored:UIImageOrientationRight;
                    break;
                default:
                    imageOrientation = isFlipped?UIImageOrientationUpMirrored:UIImageOrientationUp;
                    break;
            }
            
            filteredPhoto = [finalFilterInChain imageFromCurrentlyProcessedOutputWithOrientation:imageOrientation];
        }
        dispatch_semaphore_signal(frameRenderingSemaphore);
        
        block(filteredPhoto, error);
    }];
}

@end
