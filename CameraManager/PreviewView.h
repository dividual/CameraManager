//
//  PreviewView.h
//  CameraManagerExample
//
//  Created by Shinya Matsuyama on 3/4/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface PreviewView : UIView

@property (readonly, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (strong, nonatomic) AVCaptureSession *session;

@end
