//
//  PreviewView.h
//  CameraManagerExample
//
//  Created by Shinya Matsuyama on 3/4/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <GPUImageView.h>

//  GPUImageViewとAVCaptureVideoPreviewLayerをハイブリッドに使えるViewを作る

typedef NS_ENUM(NSInteger, PreviewViewMode)
{
    PreviewViewMode_GPUImage = 0,
    PreviewViewMode_AVCapture = 1
};

@interface PreviewView : GPUImageView

@property (readonly, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (assign, nonatomic) PreviewViewMode previewMode;

@end
