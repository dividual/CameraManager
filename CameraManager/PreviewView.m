//
//  PreviewView.m
//  CameraManagerExample
//
//  Created by Shinya Matsuyama on 3/4/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import "PreviewView.h"
#import <GPUImage/GPUImage.h>

@interface PreviewView ()
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@end

@implementation PreviewView

- (void)setup
{
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] init];
    _previewLayer.frame = self.bounds;
    
    [self.layer addSublayer:_previewLayer];
    self.previewMode = PreviewViewMode_AVCapture;
}

- (void)layoutSublayersOfLayer:(CALayer *)layer
{
    NSLog(@"layer:%@", NSStringFromClass([layer class]));
    
    if(layer == _previewLayer)
    {
        _previewLayer.frame = self.bounds;
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if(self)
    {
        [self setup];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if(self)
    {
        [self setup];
    }
    return self;
}

- (void)setPreviewMode:(PreviewViewMode)previewMode
{
    _previewMode = previewMode;
    
    //  画面に反映
    switch(_previewMode)
    {
        case PreviewViewMode_GPUImage:
            self.enabled = YES;
            self.previewLayer.opacity = 0.0;
            break;
            
        case PreviewViewMode_AVCapture:
            self.enabled = NO;
            self.previewLayer.opacity = 1.0;
            break;
    }
}

@end
