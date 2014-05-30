//
//  PreviewView.m
//  CameraManagerExample
//
//  Created by Shinya Matsuyama on 3/4/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import "PreviewView.h"

@implementation PreviewView

- (void)setup
{
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}

#pragma mark -

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

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

#pragma mark -

@dynamic previewLayer;

- (AVCaptureVideoPreviewLayer*)previewLayer
{
    return (AVCaptureVideoPreviewLayer*)self.layer;
}

@dynamic session;

- (AVCaptureSession *)session
{
	return [self.previewLayer session];
}

- (void)setSession:(AVCaptureSession *)session
{
	[self.previewLayer setSession:session];
}

@end
