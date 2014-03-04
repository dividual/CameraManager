//
//  GPUImageStillCamera+directShutter.m
//  CameraManagerExample
//
//  Created by Shinya Matsuyama on 3/4/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import "GPUImageStillCamera+directShutter.h"

@implementation GPUImageStillCamera (directShutter)

- (AVCaptureStillImageOutput*)stillImageOutput
{
    AVCaptureStillImageOutput *rep = [self valueForKey:@"photoOutput"];
    
    return rep;
}

- (void)captureDirectWithOrientation:(UIDeviceOrientation)orientation completion:(void(^)(UIImage *image, NSError *error))completion;
{
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:[[self.stillImageOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
        
        if(imageSampleBuffer == NULL)
        {
            completion(nil, error);
            return;
        }
        
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        //
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

        //
        
        UIImage *image = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:imageOrientation];
        CGImageRelease(cgImage);
        
        completion(image, nil);
    }];
}
@end
