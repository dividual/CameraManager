//
//  ViewController.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 10/23/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "ViewController.h"

@interface ViewController () <CameraViewDelegate>
@property (strong, nonatomic) UITapGestureRecognizer *tapGesture;
@property (strong, nonatomic) UITapGestureRecognizer *doubleTapGesture;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [_cameraView openCamera];
    
    //  フォーカスの処理を呼ぶためのジェスチャ
    _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [_cameraView addGestureRecognizer:_tapGesture];
    
    //  fillモードを切り替えてみる実験のためのジェスチャー
    _doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    _doubleTapGesture.numberOfTapsRequired = 2;
    [_cameraView addGestureRecognizer:_doubleTapGesture];
    
    //  カメラロールへの保存をなしで
    _cameraView.autoSaveToCameraroll = NO;
    
    //  フィルモードを変えてみる
    _cameraView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;    //kGPUImageFillModePreserveAspectRatioAndFillがフルスクリーンで使うとき
    
    //  デリゲート設定
    _cameraView.delegate = self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [_cameraView closeCamera];
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
        CGPoint pos = [_tapGesture locationInView:_cameraView];
        
        [_cameraView setFocusPoint:pos];
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer*)tapGesture
{
    if(tapGesture == _doubleTapGesture)
    {
        //  モードを変える
        if(_cameraView.fillMode == kGPUImageFillModePreserveAspectRatioAndFill)
        {
            _cameraView.fillMode = kGPUImageFillModePreserveAspectRatio;
        }
        else
        {
            _cameraView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
        }
    }
}

#pragma mark - CameraViewDelegate

- (void)cameraView:(CameraView *)sender didCapturedImage:(UIImage *)image
{
	NSLog( @"didCapturedImage:size(%f,%f)", image.size.width, image.size.height);
}

- (void)cameraView:(CameraView *)sender didChangeAdjustingFocus:(BOOL)isAdjustingFocus devide:(AVCaptureDevice *)device
{
    NSLog(@"didChangeAdjustingFocus:%d device:%@", isAdjustingFocus, device);
}

@end
