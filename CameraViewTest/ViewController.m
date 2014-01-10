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

    [CameraManager sharedManager].stillShutterButtonImageName = @"shutterButton";
    [CameraManager sharedManager].videoShutterButtonImageName = @"recButton";
    [CameraManager sharedManager].videoStopButtonImageName = @"recStopButton";
    
    [CameraManager sharedManager].videoDuration = 10.0; //   動画撮影時間

    [CameraManager sharedManager].sessionPresetForStill = AVCaptureSessionPresetPhoto;
    [CameraManager sharedManager].sessionPresetForVideo = AVCaptureSessionPreset1280x720;

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
    
    //
    _movieRecordedTime.hidden = YES;
    _movieRemainTime.hidden = YES;
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

- (void)cameraManager:(CameraManager*)sender didPlayShutterSoundWithImage:(UIImage*)image
{
    
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

- (void)cameraManagerWillStartRecordVideo:(CameraManager*)sender
{
    NSLog(@"record start");
    
    //  録画開始の音をだすならここかな 0.5秒以下
    
    //  操作してほしくないGUIを消す
    _changeCameraModeButton.hidden = YES;
    _chooseFilterButton.hidden = YES;
    
    //  秒数出すLabel表示
    _movieRecordedTime.text = @"";
    _movieRemainTime.text = @"";
    _movieRecordedTime.hidden = NO;
    _movieRemainTime.hidden = NO;
}

- (void)cameraManager:(CameraManager*)sender didRecordMovie:(NSURL*)tmpFileURL
{
    //  録画完了時
    NSLog(@"finish record");
    
    //  操作してほしくないGUIをもとに戻す
    _changeCameraModeButton.hidden = NO;
    _chooseFilterButton.hidden = NO;
    
    //  秒数出すLabel表示
    _movieRecordedTime.hidden = YES;
    _movieRemainTime.hidden = YES;
    
    //  本来ならここでアップロード処理など行う
    {
        //  あえて遅延してから消してもいいよの処理をする
        double delayTime = 1.0;
        dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, delayTime * NSEC_PER_SEC);
        dispatch_after(startTime, dispatch_get_main_queue(), ^(void){
            
            //  保存処理はここではしないのですぐに消してもいいよと伝える
            [[CameraManager sharedManager] removeTempMovieFile:tmpFileURL];
        });
    }
}

- (void)cameraManager:(CameraManager *)sender recordingTime:(NSTimeInterval)recordedTime remainTime:(NSTimeInterval)remainTime
{
    float percent = recordedTime / sender.videoDuration;
    
    _movieRecordedTime.text = [NSString stringWithFormat:@"%.1f", recordedTime];
    _movieRemainTime.text = [NSString stringWithFormat:@"-%.1f", remainTime];
    
    NSLog(@"recording:%f", percent);
}

- (BOOL)cameraManager:(CameraManager*)sender shouldChangeShutterButtonImageTo:(NSString*)imageName
{
    //  自分で画像を変更する場合は、NOを返す
    NSLog(@"shouldChangeShutterButtonImageTo:%@", imageName);
    
    for(UIButton *button in sender.shutterButtons)
    {
        [UIView transitionWithView:button duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            //
            [button setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
            
        } completion:nil];
    }
    
    return NO;
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

- (IBAction)pushedChangeModeButton:(id)sender
{
    [[CameraManager sharedManager] toggleCameraMode];
}

@end
