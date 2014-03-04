//
//  GPUImageStillCamera+CaptureOrientation.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <GPUImage/GPUImage.h>
#import "GPUImageStillCamera+Utility.h"

@interface GPUImageStillCamera (private)
- (void)capturePhotoProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withImageOnGPUHandler:(void (^)(NSError *error))block;
@end

@implementation GPUImageStillCamera (Utility)

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


///

- (void)rotateCameraWithCaptureSessionPreset:(NSString *)sessionPreset
{
	if (self.frontFacingCameraPresent == NO)
		return;
	
    NSError *error;
    AVCaptureDeviceInput *newVideoInput;
    AVCaptureDevicePosition currentCameraPosition = [[videoInput device] position];
    
    if (currentCameraPosition == AVCaptureDevicePositionBack)
    {
        currentCameraPosition = AVCaptureDevicePositionFront;
    }
    else
    {
        currentCameraPosition = AVCaptureDevicePositionBack;
    }
    
    AVCaptureDevice *backFacingCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice *device in devices)
	{
		if ([device position] == currentCameraPosition)
		{
			backFacingCamera = device;
		}
	}
    newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:backFacingCamera error:&error];
    
    if (newVideoInput != nil)
    {
        [_captureSession beginConfiguration];
        [_captureSession removeInput:videoInput];
        
        //  session切り替え
        if(![self.captureSessionPreset isEqualToString:sessionPreset])
        {
            self.captureSessionPreset = sessionPreset;
        }
        
        //
        if ([_captureSession canAddInput:newVideoInput])
        {
            [_captureSession addInput:newVideoInput];
            videoInput = newVideoInput;
        }
        else
        {
            [_captureSession addInput:videoInput];
        }
        [_captureSession commitConfiguration];
    }
    
    _inputCamera = backFacingCamera;
    [self setOutputImageOrientation:self.outputImageOrientation];
}

@end
