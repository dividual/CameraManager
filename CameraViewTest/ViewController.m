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
    _previewViewB.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    _previewViewC.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    _previewViewD.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    
    [[CameraManager sharedManager] addPreviewViewsFromArray:@[ _previewViewA, _previewViewB, _previewViewC, _previewViewD ]];
    [[CameraManager sharedManager] addFocusView:_focusView];
    
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
    [CameraManager sharedManager].flashButton = _flashButton;
    [CameraManager sharedManager].shutterButton = _shutterButton;
    [CameraManager sharedManager].cameraFrontBackButton = _cameraRotateButton;
    
    [_flashButton addTarget:[CameraManager sharedManager] action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    [_shutterButton addTarget:[CameraManager sharedManager] action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
    [_cameraRotateButton addTarget:[CameraManager sharedManager] action:@selector(rotateCameraPosition:) forControlEvents:UIControlEventTouchUpInside];
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

#pragma mark -

- (IBAction)pushedChangeFilter:(id)sender
{
    _curFilterIndex++;
    NSArray *filters = [CameraManager sharedManager].filterNameArray;
    _curFilterIndex = _curFilterIndex%filters.count;
    
    NSString *filterName = filters[_curFilterIndex];
    
    [[CameraManager sharedManager] setFilterWithName:filterName];
    
    _filterNameLabel.text = filterName;
}

- (IBAction)didChangeSilentSwitch:(id)sender
{
    [CameraManager sharedManager].silentShutterMode = _silentSwitch.isOn;
}

@end
