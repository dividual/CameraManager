//
//  ViewController.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 10/23/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "ViewController.h"
#import "UIImage+Normalize.h"
#import "CameraManager.h"

@interface ViewController () <CameraManagerDelegate>
@property (strong, nonatomic) UITapGestureRecognizer *tapGesture;
@property (strong, nonatomic) UITapGestureRecognizer *doubleTapGesture;
@property (assign, nonatomic) NSInteger curFilterIndex;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //  PreviewViewの設定
    _previewViewA.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    
    [[CameraManager sharedManager] addPreviewView:_previewViewA];
    [[CameraManager sharedManager] addFocusView:_focusView];
    
    [CameraManager sharedManager].flashAutoImageName = @"flashAuto";
    [CameraManager sharedManager].flashOffmageName = @"flashOFF";
    [CameraManager sharedManager].flashOnImageName = @"flashON";
    
    //  カメラを開く
    [[CameraManager sharedManager] openCamera];
    
    //  フォーカスの処理を呼ぶためのジェスチャ
    _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [_previewViewA addGestureRecognizer:_tapGesture];
    _tapGesture.enabled = YES;
    
    //  カメラロールへの保存するかどうか
    [CameraManager sharedManager].autoSaveToCameraroll = YES;
    
    //  デリゲート設定
    [CameraManager sharedManager].delegate = self;
    
    //  各ボタン類をつなぐ
    [[CameraManager sharedManager] addFlashButton:_flashButton];
    [[CameraManager sharedManager] addShutterButton:_shutterButton];
    [[CameraManager sharedManager] addCameraRotateButton:_cameraRotateButton];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [[CameraManager sharedManager] closeCamera];
}

#pragma mark -

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    //  CameraViewを使うときは回転してもらっては困る
    return UIInterfaceOrientationMaskPortrait;
}

#pragma mark - Gesture

- (void)handleTap:(UITapGestureRecognizer*)tapGesture
{
    if(tapGesture == _tapGesture)
    {
        CGPoint pos = [_tapGesture locationInView:_previewViewA];
        
        [[CameraManager sharedManager] setFocusPoint:pos inView:_previewViewA];
    }
}

#pragma mark - CameraViewDelegate

- (void)cameraManager:(CameraManager *)sender didCapturedImage:(UIImage *)image{
//	return;
	NSLog(@"didCapturedImage:size(%f,%f)", image.size.width, image.size.height);
    
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
//	imageView.alpha = 0.2;
    
    CGFloat width = image.size.width/image.size.height*self.view.bounds.size.height;
    imageView.frame = CGRectMake(CGRectGetWidth(self.view.bounds)/2.0 - width/2.0, 0.0, width, self.view.bounds.size.height);
    
    //
    [self.view addSubview:imageView];
    [UIView animateWithDuration:0.5 delay:0.0 options:0 animations:^{
        //
        imageView.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(90.0), 0.0, 0.0);
        
    } completion:^(BOOL finished) {
        
        [imageView removeFromSuperview];
    }];
}

- (void)cameraManager:(CameraManager *)sender didChangeAdjustingFocus:(BOOL)isAdjustingFocus devide:(AVCaptureDevice *)device
{
    NSLog(@"didChangeAdjustingFocus:%d device:%@", isAdjustingFocus, device);
}

- (void)cameraManager:(CameraManager *)sender didChangeDeviceOrientation:(UIDeviceOrientation)orientation
{
    NSLog(@"didChangeDeviceOrientation");
    
    //  UIを回す
    CGAffineTransform transform = CGAffineTransformIdentity;

    if(orientation == UIDeviceOrientationPortrait)
        transform = CGAffineTransformMakeRotation(0.0);
    else if(orientation == UIDeviceOrientationPortraitUpsideDown)
        transform = CGAffineTransformMakeRotation(M_PI);
    else if(orientation == UIDeviceOrientationLandscapeLeft)
        transform = CGAffineTransformMakeRotation(M_PI*0.5);
    else if(orientation == UIDeviceOrientationLandscapeRight)
        transform = CGAffineTransformMakeRotation(M_PI*1.5);

    //
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{

        _flashButton.transform = transform;
        _shutterButton.transform = transform;
        _cameraRotateButton.transform = transform;
        
    } completion:nil];
}

- (void)cameraManager:(CameraManager*)sender didChangeFilter:(NSString*)filterName
{
    _filterNameLabel.text = filterName;
    
    //
    [UIView animateWithDuration:0.3 delay:0.0 options:0 animations:^{
        //
        _filterNameLabel.alpha = 1.0;
        _silentSwitch.alpha = 1.0;
        
    } completion:^(BOOL finished) {
        //
    }];
}

#pragma mark -

- (IBAction)pushedChangeFilter:(id)sender
{
    if(![CameraManager sharedManager].isChooseFilterMode)
    {
        [UIView animateWithDuration:0.3 delay:0.0 options:0 animations:^{
            //
            _filterNameLabel.alpha = 0.0;
            _silentSwitch.alpha = 0.0;
            
        } completion:^(BOOL finished) {
            //
        }];
        
        //
        [[CameraManager sharedManager] showChooseEffectInPreviewView:_previewViewA];
    }
    else
    {
        [[CameraManager sharedManager] dissmissChooseEffect];
    }
}

- (IBAction)didChangeSilentSwitch:(id)sender
{
    [CameraManager sharedManager].silentShutterMode = _silentSwitch.isOn;
}

@end
