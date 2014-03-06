//
//  ViewController.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 10/23/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "ViewController.h"
#import <NSObject+EventDispatcher/NSObject+EventDispatcher.h>

#import "UIImage+Normalize.h"
#import "CameraManager.h"
#import "PreviewView.h"
#import "CameraManager.h"

@interface ViewController ()
@property (strong, nonatomic) UITapGestureRecognizer *tapGesture;
@property (strong, nonatomic) UIPinchGestureRecognizer *pinchGesture;
@property (assign, nonatomic) NSInteger curFilterIndex;
@property (assign, nonatomic) CGSize originalFocusCursorSize;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //  PreviewViewの設定
    _focusView.image = [[UIImage imageNamed:@"focusFrame"] stretchableImageWithLeftCapWidth:4.0 topCapHeight:4.0];
    
    //  カメラを開く前に設定をしておく
    [CameraManager sharedManager].videoDuration = 3.0; //   動画撮影時間
    [CameraManager sharedManager].autoSaveToCameraroll = YES;
    
    //  通常撮影の静止画の時
    [CameraManager sharedManager].sessionPresetForStill = AVCaptureSessionPresetPhoto;
    [CameraManager sharedManager].sessionPresetForFrontStill = AVCaptureSessionPresetPhoto;
    
    //  サイレントモードの時の設定
    [CameraManager sharedManager].sessionPresetForSilentStill = AVCaptureSessionPresetHigh;
    [CameraManager sharedManager].sessionPresetForSilentFrontStill = AVCaptureSessionPresetHigh;
    
    //  フォーカスのビューを消しておく
    _focusView.alpha = 0.0;
    _originalFocusCursorSize = _focusView.bounds.size;
    
    //  カメラ準備できるまでは全部OFFで
    _shutterButton.enabled = NO;
    _cameraRotateButton.enabled = NO;
    _flashButton.enabled = NO;
    _changeCameraModeButton.enabled = NO;
    _silentSwitch.enabled = NO;
    
    //  フォーカスの処理を呼ぶためのジェスチャ
    _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [_previewView addGestureRecognizer:_tapGesture];
    _tapGesture.enabled = YES;
    
    //  ズームのジェスチャ
    _pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [_previewView addGestureRecognizer:_pinchGesture];
    _pinchGesture.enabled = YES;
    
    //  カメラロールへの保存するかどうか
    [CameraManager sharedManager].autoSaveToCameraroll = YES;
        
    //
    _movieRecordedTime.hidden = YES;
    _movieRemainTime.hidden = YES;
    
    //  プレビュー設定
    [_previewView.previewLayer setSession:[CameraManager sharedManager].session];
    //_previewView.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _previewView.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    //  プレビュー画面をalphaゼロから
    _previewView.alpha = 0.0;


    //  イベント登録
    [[CameraManager sharedManager] addEventListener:@"open" observer:self
                                           selector:@selector(cameraManagerOpened:)];
    
    [[CameraManager sharedManager] addEventListener:@"close" observer:self
                                           selector:@selector(cameraManagerClosed:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeDeviceOrientation" observer:self
                                           selector:@selector(cameraManagerdidChangeDeviceOrientation:)];
    
    [[CameraManager sharedManager] addEventListener:@"didCapturedImageForAnimation" observer:self
                                           selector:@selector(cameraManagerDidCapturedImageForAnimation:)];
    
    [[CameraManager sharedManager] addEventListener:@"didCapturedImage" observer:self
                                           selector:@selector(cameraManagerDidCapturedImage:)];
    
    [[CameraManager sharedManager] addEventListener:@"willStartVideoRecording" observer:self
                                           selector:@selector(cameraManagerWillStartVideoRecording:)];
    
    [[CameraManager sharedManager] addEventListener:@"didStartVideoRecording" observer:self
                                           selector:@selector(cameraManagerDidStartVideoRecording:)];
    
    [[CameraManager sharedManager] addEventListener:@"didFinishedVideoRecording" observer:self
                                           selector:@selector(cameraManagerDidFinishedVideoRecording:)];

    [[CameraManager sharedManager] addEventListener:@"recordingVideo" observer:self
                                           selector:@selector(cameraManagerRecordingVideo:)];
    
    [[CameraManager sharedManager] addEventListener:@"willChangeCameraMode" observer:self
                                           selector:@selector(cameraManagerWillChangeCameraMode:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeCameraMode" observer:self
                                           selector:@selector(cameraManagerDidChangeCameraMode:)];
    
    [[CameraManager sharedManager] addEventListener:@"willChangeCameraFrontBack" observer:self
                                           selector:@selector(cameraManagerWillChangeCameraFrontBack:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeCameraFrontBack" observer:self
                                           selector:@selector(cameraManagerDidChangeCameraFrontBack:)];
    
    [[CameraManager sharedManager] addEventListener:@"showFocusCursor" observer:self
                                           selector:@selector(cameraManagerShowFocusCursor:)];
    
    [[CameraManager sharedManager] addEventListener:@"hideFocusCursor" observer:self
                                           selector:@selector(cameraManagerHideFocusCursor:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeFlashMode" observer:self
                                           selector:@selector(cameraManagerDidChangeFlashMode:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeIsCapturingStillImage" observer:self
                                           selector:@selector(cameraManagerDidChangeIsCapturingStillImage:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeIsRecordingVideo" observer:self
                                           selector:@selector(cameraManagerDidChangeIsRecordingVideo:)];
    
    [[CameraManager sharedManager] addEventListener:@"willChangeSilentMode" observer:self
                                           selector:@selector(cameraManagerWillChangeSilentMode:)];
    
    [[CameraManager sharedManager] addEventListener:@"didChangeSilentMode" observer:self
                                           selector:@selector(cameraManagerDidChangeSilentMode:)];
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

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
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
        CGPoint pos = [_tapGesture locationInView:_previewView];
        
        CGPoint fixPos = [_previewView.previewLayer captureDevicePointOfInterestForPoint:pos];
        [[CameraManager sharedManager] setFocusPoint:fixPos];
    }
}

#pragma mark - animations

- (void)cameraGUIUpdate
{
    //  カメラの状態に応じてGUIの表示を切り替える
    
    //  フラッシュの有り無しでflashボタンの表示/非表示
    _flashButton.hidden = ![[CameraManager sharedManager] hasFlash];
    
    //  フロントカメラ、もしくはリアカメラのみの場合にrotateアイコン消す
    BOOL isFrontCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
    BOOL isRearCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
    if(!isFrontCameraAvailable || !isRearCameraAvailable)
    {
        _cameraRotateButton.hidden = YES;
    }
    else
        _cameraRotateButton.hidden = NO;
}

#pragma mark - CameraViewDelegate

- (void)cameraManagerOpened:(NSNotification*)notification
{
    NSLog(@"cameraManager:open");
    
    //
    [self cameraGUIUpdate];
    
    //  ここでもあらためて明示的に書いておく（最終的には、AVLayerVideoGravityResizeAspectFillになる）
    _previewView.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    //
    [UIView animateWithDuration:0.3 delay:0.0 options:0 animations:^{
        //
        _previewView.alpha = 1.0;
        
    } completion:^(BOOL finished) {
        //
        _shutterButton.enabled = YES;
        _cameraRotateButton.enabled = YES;
        _flashButton.enabled = YES;
        _changeCameraModeButton.enabled = YES;
        _silentSwitch.enabled = YES;
    }];
}

- (void)cameraManagerClosed:(NSNotification*)notification
{
    NSLog(@"cameraManager:close");
    
    //
    _shutterButton.enabled = NO;
    _cameraRotateButton.enabled = NO;
    _flashButton.enabled = NO;
    _changeCameraModeButton.enabled = NO;
    _silentSwitch.enabled = NO;
    
    _previewView.alpha = 0.0;
}

- (void)cameraManagerdidChangeDeviceOrientation:(NSNotification*)notification
{
    NSNumber *orientationNum = notification.userInfo[@"orientation"];
    UIDeviceOrientation orientation = orientationNum.integerValue;
    
    NSLog(@"cameraManager:didChangeDeviceOrientation(orientation = %d)", (int)orientation);
    
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

- (void)cameraManagerDidCapturedImage:(NSNotification*)notification
{
    UIImage *image = notification.userInfo[@"image"];

    NSLog(@"cameraManager:didCapturedImage(image = %@)", NSStringFromCGSize(image.size));
    
    //  GUIを元に戻す
    _shutterButton.enabled = YES;
    _cameraRotateButton.enabled = YES;
    _flashButton.enabled = YES;
    
    //
    _changeCameraModeButton.enabled = YES;
    _silentSwitch.enabled = YES;
}

- (void)cameraManagerDidCapturedImageForAnimation:(NSNotification*)notification
{
    UIImage *image = notification.userInfo[@"image"];
    
    NSLog(@"cameraManager:didCapturedImageForAnimation(image = %@)", NSStringFromCGSize(image.size));
    
    //  アニメーション表示してみる
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    
    CGFloat scaleW = CGRectGetWidth(self.view.bounds)/image.size.width;
    CGFloat scaleH = CGRectGetHeight(self.view.bounds)/image.size.height;
    CGFloat scale = MIN(scaleW, scaleH);
    
    imageView.frame = CGRectMake(0.0, 0.0, scale*image.size.width, scale*image.size.height);
    imageView.center = CGPointMake(CGRectGetWidth(self.view.bounds)/2.0, CGRectGetHeight(self.view.bounds)/2.0);
    
    [self.view addSubview:imageView];
    
    [UIView animateWithDuration:0.3 delay:0.0 options:0 animations:^{
        //
        imageView.transform = CGAffineTransformMakeScale(0.01, 0.01);
        //imageView.alpha = 0.0;
        
    } completion:^(BOOL finished) {
        //
        [imageView removeFromSuperview];
        
    }];
}

- (void)cameraManagerWillStartVideoRecording:(NSNotification*)notification
{
    NSLog(@"cameraManager:willStartVideoRecording");
    
    //  操作してほしくないGUIを消す
    _changeCameraModeButton.hidden = YES;
    
    //  Shutter以外消す
    _flashButton.hidden = YES;
    _cameraRotateButton.hidden = YES;
    _silentSwitch.hidden = YES;
    
    //  秒数出すLabel表示
    _movieRecordedTime.text = @"";
    _movieRemainTime.text = @"";
    _movieRecordedTime.hidden = NO;
    _movieRemainTime.hidden = NO;
    
    //
    [UIView transitionWithView:_shutterButton duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        //
        [_shutterButton setImage:[UIImage imageNamed:@"recStopButton"] forState:UIControlStateNormal];
        
    } completion:nil];
}

- (void)cameraManagerDidStartVideoRecording:(NSNotification*)notification
{
    NSLog(@"cameraManager:didStartVideoRecording");
}

- (void)cameraManagerDidFinishedVideoRecording:(NSNotification*)notification
{
    NSURL *movieURL = notification.userInfo[@"movieURL"];
    
    NSLog(@"cameraManager:didFinishedVideoRecording(URL = %@)", movieURL);
    
    //  録画完了時    
    //  GUIを元に戻す
    _changeCameraModeButton.hidden = NO;
    _flashButton.hidden = NO;
    _cameraRotateButton.hidden = NO;
    _silentSwitch.hidden = NO;
    
    //
    _shutterButton.enabled = YES;
    _cameraRotateButton.enabled = YES;
    _flashButton.enabled = YES;
    
    //
    _changeCameraModeButton.enabled = YES;
    _silentSwitch.enabled = YES;
    
    //  秒数出すLabel消す
    _movieRecordedTime.hidden = YES;
    _movieRemainTime.hidden = YES;
    
    //  ボタンを戻す
    [UIView transitionWithView:_shutterButton duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        //
        [_shutterButton setImage:[UIImage imageNamed:@"recButton"] forState:UIControlStateNormal];
        
    } completion:nil];
    
    //  本来ならここでアップロード処理など行う
    {
        //  あえて遅延してから消してもいいよの処理をする
        double delayTime = 1.0;
        dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, delayTime * NSEC_PER_SEC);
        dispatch_after(startTime, dispatch_get_main_queue(), ^(void){
            
            //  保存処理はここではしないのですぐに消してもいいよと伝える
            [[CameraManager sharedManager] removeTempMovieFile:movieURL];
        });
    }
}

- (void)cameraManagerRecordingVideo:(NSNotification*)notification
{
    NSNumber *timeNum = notification.userInfo[@"time"];
    NSNumber *remainTimeNum = notification.userInfo[@"remainTime"];
    NSTimeInterval time = timeNum.doubleValue;
    NSTimeInterval remainTime = remainTimeNum.doubleValue;
    
    NSLog(@"cameraManager:recordingVideo(time = %f, remainTime = %f)", time, remainTime);
    
    //
    float percent = time / [CameraManager sharedManager].videoDuration;
    
    _movieRecordedTime.text = [NSString stringWithFormat:@"%.1f", time];
    _movieRemainTime.text = [NSString stringWithFormat:@"-%.1f", remainTime];
    
    NSLog(@"recording:%f", percent);
}

- (void)cameraManagerWillChangeCameraMode:(NSNotification*)notification
{
    NSNumber *modeNum = notification.userInfo[@"mode"];
    CMCameraMode mode = modeNum.integerValue;
    
    NSLog(@"cameraManager:willChangeCameraMode(mode = %d)", (int)mode);
    
    //  GUIボタンを切り替える
    if(mode == CMCameraModeVideo)
        [_shutterButton setImage:[UIImage imageNamed:@"recButton"] forState:UIControlStateNormal];
    else
        [_shutterButton setImage:[UIImage imageNamed:@"shutterButton"] forState:UIControlStateNormal];
}

- (void)cameraManagerDidChangeCameraMode:(NSNotification*)notification
{
    NSNumber *modeNum = notification.userInfo[@"mode"];
    CMCameraMode mode = modeNum.integerValue;
    
    NSLog(@"cameraManager:didChangeCameraMode(mode = %d)", (int)mode);
    
    //  GUIを元に戻す
    _shutterButton.enabled = YES;
    _cameraRotateButton.enabled = YES;
    _flashButton.enabled = YES;
    
    //
    _changeCameraModeButton.enabled = YES;
    _silentSwitch.enabled = YES;
    
    //  画面を元に
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        //
        _previewView.alpha = 1.0;
        
    } completion:nil];
}

- (void)cameraManagerWillChangeCameraFrontBack:(NSNotification*)notification
{
    NSNumber *positionNum = notification.userInfo[@"position"];
    AVCaptureDevicePosition position = positionNum.integerValue;
    
    NSLog(@"cameraManager:willChangeCameraFrontBack(position = %d)", (int)position);
}

- (void)cameraManagerDidChangeCameraFrontBack:(NSNotification*)notification
{
    NSNumber *positionNum = notification.userInfo[@"position"];
    AVCaptureDevicePosition position = positionNum.integerValue;

    NSLog(@"cameraManager:didChangeCameraFrontBack(position = %d)", (int)position);
    
    [self cameraGUIUpdate];
    
    //  アクティブ化
    _cameraRotateButton.enabled = YES;
    _shutterButton.enabled = YES;
    _flashButton.enabled = YES;
    
    //
    _changeCameraModeButton.enabled = YES;
    _silentSwitch.enabled = YES;
    
    //  切替時に画面に変化をいれてみる
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        //
        _previewView.alpha = 1.0;
        
    } completion:^(BOOL finished) {
        //
    }];

}
- (void)cameraManagerShowFocusCursor:(NSNotification*)notification
{
    //  フィルター選択画面中は表示しない
    if([CameraManager sharedManager].isChooseFilterMode)
        return;
    
    NSValue *positionValue = notification.userInfo[@"position"];
    CGPoint focusPos = positionValue.CGPointValue;
    CGPoint fixFocusPos = [_previewView.previewLayer pointForCaptureDevicePointOfInterest:focusPos];
    
    NSNumber *isContinuousNum = notification.userInfo[@"isContinuous"];
    BOOL isContinuous = isContinuousNum.boolValue;
    
    NSLog(@"cameraManager:showFocusCursor(postion = %@, isContinuous = %d)", NSStringFromCGPoint(fixFocusPos), isContinuous);
    
    //  フォーカスが出てくるアニメーション
    if(isContinuous)
        _focusView.bounds = CGRectMake(0.0, 0.0, _originalFocusCursorSize.width*8.0, _originalFocusCursorSize.height*8.0);
    else
        _focusView.bounds = CGRectMake(0.0, 0.0, _originalFocusCursorSize.width*4.0, _originalFocusCursorSize.height*4.0);

    _focusView.center = fixFocusPos;

    //
    [_focusView.layer removeAllAnimations];
    _focusView.alpha = 0.0;

    [UIView animateWithDuration:0.1 delay:0.0 options:7<<16 animations:^{
        //
        _focusView.bounds = CGRectMake(0.0, 0.0, _originalFocusCursorSize.width, _originalFocusCursorSize.height);
        _focusView.center = fixFocusPos;

        //
        _focusView.alpha = 1.0;

    } completion:^(BOOL finished) {
        //
        if(finished)
        {
            _focusView.alpha = 1.0;
            [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse animations:^{
                //
                _focusView.alpha = 0.3;
                
            } completion:^(BOOL finished) {
                //
            }];
        }
    }];
}

- (void)cameraManagerHideFocusCursor:(NSNotification*)notification
{
    NSLog(@"cameraManager:hideFocusCursor");
    
    //  フォーカスを消す
    [UIView animateWithDuration:0.2 delay:0.0 options:7<<16 animations:^{
        //
        CGPoint center = _focusView.center;
        _focusView.bounds = CGRectMake(0.0, 0.0, 0.0, 0.0);
        _focusView.center = center;
        
        //
        _focusView.alpha = 0.0;
        
    } completion:^(BOOL finished) {
        //
        
    }];
}

- (void)cameraManagerDidChangeFlashMode:(NSNotification*)notification
{
    NSNumber *flashModeNum = notification.userInfo[@"mode"];
    CMFlashMode mode = flashModeNum.integerValue;
    
    NSLog(@"cameraManager:didChangeFlashMode(mode = %d)", (int)mode);
    
    //  flashボタンの画像を切り替える
    NSString *imgName = nil;
    switch(mode)
    {
        case CMFlashModeAuto:
            imgName = @"flashAuto";
            break;

        case CMFlashModeOff:
            imgName = @"flashOFF";
            break;

        case CMFlashModeOn:
            imgName = @"flashON";
            break;
    }

    if(imgName)
    {
        UIImage *img = [UIImage imageNamed:imgName];
        if(img)
        {
            [_flashButton setImage:img forState:UIControlStateNormal];
        }
    }
}

- (void)cameraManagerDidChangeIsCapturingStillImage:(NSNotification*)notification
{
    NSNumber *stateNum = notification.userInfo[@"state"];
    BOOL state = stateNum.boolValue;
    
    NSLog(@"cameraManagerDidChangeIsCapturingStillImage:%d", state);
    
    if(state)
    {
        //  アニメーションいれてみる
        _previewView.alpha = 0.0;
        
        [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
            //
            _previewView.alpha = 1.0;
            
        } completion:^(BOOL finished) {
            //
            
        }];
    }
}

- (void)cameraManagerDidChangeIsRecordingVideo:(NSNotification*)notification
{
    NSNumber *stateNum = notification.userInfo[@"state"];
    BOOL state = stateNum.boolValue;
    
    NSLog(@"cameraManagerDidChangeIsRecordingVideo:%d", state);
    
}

- (void)cameraManagerWillChangeSilentMode:(NSNotification*)notification
{
    NSLog(@"cameraManagerWillChangeSilentMode");
    
    //  画面を暗く
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        //
        _previewView.alpha = 0.0;
        
    } completion:nil];
}

- (void)cameraManagerDidChangeSilentMode:(NSNotification*)notification
{
    NSLog(@"cameraManagerDidChangeSilentMode");
    
    //  画面を戻す
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        //
        _previewView.alpha = 1.0;
        
    } completion:nil];
}

////////////

#pragma mark - 

/// カメラのオンオフ
- (IBAction)didChangeCameraEnableSwitch:(UISwitch*)sender{
	if( sender.isOn ){
		[[CameraManager sharedManager] openCamera];
	} else {
		[[CameraManager sharedManager] closeCamera];
	}
}

- (IBAction)didChangeSilentSwitch:(id)sender
{
    [CameraManager sharedManager].silentShutterMode = _silentSwitch.isOn;
}

- (IBAction)pushedChangeModeButton:(id)sender
{
    //  操作できないように消す
    _shutterButton.enabled = NO;
    _cameraRotateButton.enabled = NO;
    _flashButton.enabled = NO;
    
    //
    _changeCameraModeButton.enabled = NO;
    _silentSwitch.enabled = NO;
    
    //
    [[CameraManager sharedManager] toggleCameraMode];
    
    //  画面を暗く
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        //
        _previewView.alpha = 0.0;
        
    } completion:nil];
}

- (IBAction)pushedShutterButton:(id)sender
{
    if([CameraManager sharedManager].cameraMode == CMCameraModeStill && [CameraManager sharedManager].silentShutterMode)
    {
        //  アニメーションいれてみる
        _previewView.alpha = 0.0;
        
        [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
            //
            _previewView.alpha = 1.0;
            
        } completion:^(BOOL finished) {
            //
            
        }];
    }
    
    //  その他のGUIも操作できないように消す
    _cameraRotateButton.enabled = NO;
    _flashButton.enabled = NO;
    
    //
    _changeCameraModeButton.enabled = NO;
    _silentSwitch.enabled = NO;
    
    //
    [[CameraManager sharedManager] takePhoto];
}

- (IBAction)pushedFlashButton:(id)sender
{
    [[CameraManager sharedManager] changeFlashMode];
}

- (IBAction)pushedCameraRotate:(id)sender
{
    //  連打防止とエラー防止
    _cameraRotateButton.enabled = NO;
    _shutterButton.enabled = NO;
    _flashButton.enabled = NO;
    
    //
    _changeCameraModeButton.enabled = NO;
    _silentSwitch.enabled = NO;
    
    //  入れ替え処理
    [[CameraManager sharedManager] rotateCameraPosition];

    //  切替時に画面に変化をいれてみる
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        _previewView.alpha = 0.0;
    } completion:nil];
}

#pragma mark - zoom

- (void)handlePinch:(UIPinchGestureRecognizer*)gesture
{
    if(gesture == _pinchGesture)
    {
        switch(_pinchGesture.state)
        {
            case UIGestureRecognizerStatePossible:
                break;
                
            case UIGestureRecognizerStateBegan:
            {
                CGFloat currentScale = [CameraManager sharedManager].zoomScale;
                _pinchGesture.scale = currentScale;
            }
                
            case UIGestureRecognizerStateChanged:
                [CameraManager sharedManager].zoomScale = _pinchGesture.scale;
                break;
                
            case UIGestureRecognizerStateEnded:
                break;
                
            case UIGestureRecognizerStateCancelled:
                break;
                
            case UIGestureRecognizerStateFailed:
                break;
        }
    }
}

@end
