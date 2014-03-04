//
//  GPUImageStillCamera+CaptureOrientation.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 11/4/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

@class GPUImage;

@interface GPUImageStillCamera (Utility)

- (void)captureFixFlipPhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block;

- (void)captureFixFlipPhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain orientation:(UIDeviceOrientation)orientation withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block;

//  前後のカメラ入れ替えメソッドが不満だったので解像度指定するバージョンを作った
- (void)rotateCameraWithCaptureSessionPreset:(NSString *)sessionPreset;


@end
