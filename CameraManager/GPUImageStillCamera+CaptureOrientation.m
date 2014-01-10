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
            BOOL isFront = self.cameraPosition == AVCaptureDevicePositionFront?YES:NO;
        
            UIImageOrientation imageOrientation = UIImageOrientationLeft;
            switch (orientation)
            {
                case UIDeviceOrientationPortrait:
                    imageOrientation = UIImageOrientationUp;
                    break;
                case UIDeviceOrientationPortraitUpsideDown:
                    imageOrientation = UIImageOrientationDown;
                    break;
                case UIDeviceOrientationLandscapeLeft:
                    imageOrientation = isFront?UIImageOrientationRight:UIImageOrientationLeft;
                    break;
                case UIDeviceOrientationLandscapeRight:
                    imageOrientation = isFront?UIImageOrientationLeft:UIImageOrientationRight;
                    break;
                default:
                    imageOrientation = UIImageOrientationUp;
                    break;
            }
            
            filteredPhoto = [finalFilterInChain imageFromCurrentlyProcessedOutputWithOrientation:imageOrientation];
        }
        dispatch_semaphore_signal(frameRenderingSemaphore);
        
        block(filteredPhoto, error);
    }];
}

- (void)captureFixFlipPhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block
{
    //    reportAvailableMemoryForGPUImage(@"Before Capture");
    
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        NSData *dataForJPEGFile = nil;
        
        if(!error){
            @autoreleasepool {
                BOOL isFront = self.cameraPosition == AVCaptureDevicePositionFront?YES:NO;
                
                UIImageOrientation imageOrientation = UIImageOrientationLeft;
                switch (orientation)
                {
                    case UIDeviceOrientationPortrait:
                        imageOrientation = UIImageOrientationUp;
                        break;
                    case UIDeviceOrientationPortraitUpsideDown:
                        imageOrientation = UIImageOrientationDown;
                        break;
                    case UIDeviceOrientationLandscapeLeft:
                        imageOrientation = isFront?UIImageOrientationRight:UIImageOrientationLeft;
                        break;
                    case UIDeviceOrientationLandscapeRight:
                        imageOrientation = isFront?UIImageOrientationLeft:UIImageOrientationRight;
                        break;
                    default:
                        imageOrientation = UIImageOrientationUp;
                        break;
                }
                
                UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentlyProcessedOutputWithOrientation:imageOrientation
                                          ];
                dispatch_semaphore_signal(frameRenderingSemaphore);
                //                reportAvailableMemoryForGPUImage(@"After UIImage generation");
                
                dataForJPEGFile = UIImageJPEGRepresentation(filteredPhoto,self.jpegCompressionQuality);
                //                reportAvailableMemoryForGPUImage(@"After JPEG generation");
            }
            
            //            reportAvailableMemoryForGPUImage(@"After autorelease pool");
        }else{
            dispatch_semaphore_signal(frameRenderingSemaphore);
        }
        
        block(dataForJPEGFile, error);
    }];
}

@end
