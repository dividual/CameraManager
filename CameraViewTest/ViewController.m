//
//  ViewController.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 10/23/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "ViewController.h"
#import "UIImage+Normalize.h"

@interface ViewController () <CameraViewDelegate>
@property (strong, nonatomic) UITapGestureRecognizer *tapGesture;
@property (strong, nonatomic) UITapGestureRecognizer *doubleTapGesture;
@property (assign, nonatomic) NSInteger curFilterIndex;
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
    _tapGesture.enabled = NO;
    
    //  fillモードを切り替えてみる実験のためのジェスチャー
    _doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    _doubleTapGesture.numberOfTapsRequired = 2;
    [_cameraView addGestureRecognizer:_doubleTapGesture];
    _doubleTapGesture.enabled = NO;
    
    //  カメラロールへの保存するかどうか
    _cameraView.autoSaveToCameraroll = YES;
    
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
	NSLog(@"didCapturedImage:size(%f,%f)", image.size.width, image.size.height);
    
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    
    CGFloat width = image.size.width/image.size.height*self.view.bounds.size.height;
    imageView.frame = CGRectMake(CGRectGetWidth(self.view.bounds)/2.0 - width/2.0, 0.0, width, self.view.bounds.size.height);
    
    //
    [self.view addSubview:imageView];
    [UIView animateWithDuration:0.5 delay:0.0 options:0 animations:^{
        //
        imageView.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(90.0), 0.0, 0.0);
        
    } completion:^(BOOL finished) {
        
#warning ここは消すのが本当なんだけど、消さないと表示が止まっていたので、あえてそうしてる。
        [imageView removeFromSuperview];
    }];
}

- (void)cameraView:(CameraView *)sender didChangeAdjustingFocus:(BOOL)isAdjustingFocus devide:(AVCaptureDevice *)device
{
    NSLog(@"didChangeAdjustingFocus:%d device:%@", isAdjustingFocus, device);
}

#pragma mark -

- (IBAction)pushedChangeFilter:(id)sender
{
    _curFilterIndex++;
    NSArray *filters = _cameraView.filterNameArray;
    _curFilterIndex = _curFilterIndex%filters.count;
    
    NSString *filterName = filters[_curFilterIndex];
    
    [_cameraView setFilterWithName:filterName];
    
    _filterNameLabel.text = filterName;
}

@end
