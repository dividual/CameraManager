//
//  CameraView.m
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "CameraView.h"
#import "UIView+utility.h"
#import <AssetsLibrary/AssetsLibrary.h>

@interface CameraView ()
@property (strong, nonatomic) GPUImageStillCamera *stillCamera;
@property (strong, nonatomic) GPUImageOutput<GPUImageInput> *filter;
@property (assign, nonatomic) BOOL hasCamera;
@end

#pragma mark -

@implementation CameraView

- (void)setup
{
    //  初期化処理
    
    //  エフェクト用のFilterを設定
    _filter = [[GPUImageFilter alloc] init];
    
    //  デフォルトのフラッシュモード指定しておく
    _flashMode = FLASH_MODE_OFF;
    
    //  デフォルトのdelaytime
    _delayTimeForFlash = 0.25;
    
    //  デフォルトはカメラロール保存自動
    _autoSaveToCameraroll = YES;
    
    //  デフォルトのJpegQuality
    _jpegQuality = 0.8;
    
    //  表示はめいっぱいに広げる
    self.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
}

#pragma mark -

- (void)moveToSelfSubviews:(UIView*)view
{
    if(![self.subviews containsObject:view])
    {
        [view removeFromSuperviewAndAddToParentView:self];
    }
}

- (void)openCamera
{
    NSLog(@"setUpCamera");

    //  フォーカスのImageViewを消しておく
    _focusFrameView.alpha = 0;
    
    //  ビューを自分の中に
    [self moveToSelfSubviews:_focusFrameView];
    
    //  念のためフォーカスのImageViewを最前面にしておく
    [self bringSubviewToFront:_focusFrameView];
    
    //  各ボタン類の繋ぎ込み
    if(_shutterButton)
        [_shutterButton addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
    
    if(_flashButton)
        [_flashButton addTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    
    if(_cameraFrontBackButton)
        [_cameraFrontBackButton addTarget:self action:@selector(rotateCameraPosition:) forControlEvents:UIControlEventTouchUpInside];
    
    
    //  バックグラウンドで実行
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{

        //  カメラが使えるかどうか調べる
        if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
        {
            //  カメラある
            
            //  GPUImageStillCamera作る
            _stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:AVCaptureDevicePositionBack];
            _stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
            
            //  forcusの監視をする
            [_stillCamera.inputCamera addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:nil];
            
            //
            runOnMainQueueWithoutDeadlocking(^{
                
                [_stillCamera startCameraCapture];
                
                //  出力するように設定
                [self prepareFilter];
                
                //  フラッシュがないときは表示消す
                if(![_stillCamera.inputCamera hasTorch])
                {
                    _flashButton.hidden = YES;
                }
            });
        }
        else
        {
            //  カメラがないときはとりあえずなにもしない
        }

    });
}

- (void)closeCamera
{
    [_stillCamera stopCameraCapture];
    [self removeAllTargets];
    
    //  forcusの監視をやめる
    [_stillCamera.inputCamera removeObserver:self forKeyPath:@"adjustingFocus"];
    
    //
    _stillCamera = nil;
}

-(void)prepareFilter
{
    _hasCamera = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
    
    if(_hasCamera)
    {
        NSLog(@"prepareLiveFilter");
        [self prepareLiveFilter];
    }
    else
    {
        NSLog(@"no camera");
        //  カメラないときはとりあえず何もしない
        //[self prepareStaticFilter];
    }
}

- (void)prepareLiveFilter
{
    //  リアルタイム処理のフィルター準備
    [_stillCamera addTarget:_filter];
    [_filter addTarget:self];
    
    [_filter prepareForImageCapture];
}

- (void)removeAllTargets
{
    [_stillCamera removeAllTargets];
    
    //regular filter
    [_filter removeAllTargets];
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

#pragma mark -

- (CGRect)inputImageRect
{
    //  GPUImageViewに表示してる元画像のサイズ
    NSValue *inputSizeValue = [self valueForKey:@"inputImageSize"];
    if(inputSizeValue)
    {
        CGSize inputSize = [inputSizeValue CGSizeValue];
        
        CGFloat width = inputSize.width;
        CGFloat height = inputSize.height;
        CGFloat viewWidth = CGRectGetWidth(self.bounds);
        CGFloat viewHeight = CGRectGetHeight(self.bounds);
        
        CGFloat scaleW = viewWidth/width;
        CGFloat scaleH = viewHeight/height;
        CGFloat scale = MAX(scaleW, scaleH);
        
        width *= scale;
        height *= scale;
        
        CGRect rect = CGRectMake(viewWidth/2.0 - width/2.0, viewHeight/2.0 - height/2.0, width, height);
                
        return rect;
    }
    
    NSLog(@"can't get inputImageSize");
    
    return self.bounds;
}

- (CGPoint)convertToInterestPointFromTouchPos:(CGPoint)pos
{
    CGRect inputRect = [self inputImageRect];
    
    CGPoint fixPos = CGPointMake(pos.x-inputRect.origin.x, pos.y-inputRect.origin.y);
    
    CGFloat xx = fixPos.x/CGRectGetWidth(inputRect);
    CGFloat yy = fixPos.y/CGRectGetHeight(inputRect);
    
    return CGPointMake(yy, 1.0-xx);
}

- (CGPoint)convertToTouchPosFromInterestPoint:(CGPoint)pos
{
    CGRect inputRect = [self inputImageRect];
    
    pos = CGPointMake(1.0-pos.y, pos.x);
    
    CGPoint fixPos = CGPointMake(pos.x*CGRectGetWidth(inputRect) + inputRect.origin.x, pos.y*CGRectGetHeight(inputRect) + inputRect.origin.y);
    
    return fixPos;
}

#pragma mark -

- (void)setFocusPoint:(CGPoint)pos
{
    if(!CGRectContainsPoint(self.bounds, pos))
        return;
    
    //
    AVCaptureDevice *device = _stillCamera.inputCamera;
    CGSize frameSize = self.frame.size;
    
    if ([_stillCamera cameraPosition] == AVCaptureDevicePositionFront)
    {
        //  前のカメラでプレビューするときは左右反対になる
        pos.x = frameSize.width - pos.x;
    }
    
    //  座標変換
    CGPoint pointOfInterest = [self convertToInterestPointFromTouchPos:pos];
    
    //  タッチした位置へのフォーカスをサポートするかチェック
    if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus])
    {
        NSError *error;
        if([device lockForConfiguration:&error])    //  devicelock
        {
            //  フォーカスを合わせる位置を指定
            [device setFocusPointOfInterest:pointOfInterest];
            [device setFocusMode:AVCaptureFocusModeAutoFocus];
            
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            {
                [device setExposurePointOfInterest:pointOfInterest];
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            }
            
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"ERROR = %@", error);
        }
    }
}

- (void)setFlashMode:(NSInteger)flashMode
{
    _flashMode = flashMode;
    
    //
    NSString *imgName = nil;
    switch(_flashMode)
    {
        case FLASH_MODE_AUTO:
            imgName = _flashAutoImageName;
            break;
            
        case FLASH_MODE_OFF:
            imgName = _flashOffmageName;
            break;
            
        case FLASH_MODE_ON:
            imgName = _flashOnImageName;
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

#pragma mark - IBAction

#pragma mark - IBAction

- (IBAction)changeFlashMode:(id)sender
{
    //  flashモードのボタンを押された
    self.flashMode = (_flashMode+1)%3;
}

- (IBAction)takePhoto:(id)sender
{
    //  シャッターボタンを押された
    _shutterButton.enabled = NO;
    
    _cameraFrontBackButton.alpha = 0.0;
    _flashButton.alpha = 0.0;
    
    if (_hasCamera)
    {
        [self prepareForCapture];
    }
    else
    {
        //  カメラがないときは何もしない
    }
}

- (IBAction)rotateCameraPosition:(id)sender
{
    _cameraFrontBackButton.enabled = NO;
    [_stillCamera rotateCamera];
    _cameraFrontBackButton.enabled = YES;
    
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera] && _stillCamera)
    {
        if ([_stillCamera.inputCamera hasFlash] && [_stillCamera.inputCamera hasTorch])
        {
            _flashButton.alpha = 1.0;
        }
        else
        {
            _flashButton.alpha = 0.0;
        }
    }
}

#pragma mark - capture

- (void)prepareForCapture
{
    //  ロック
    [_stillCamera.inputCamera lockForConfiguration:nil];
    
    //  フラッシュの準備（上記のロックをかけてからでないと処理できないっぽい）
    if(_flashMode == FLASH_MODE_AUTO && [_stillCamera.inputCamera hasTorch])
    {
        //  自動
        [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeAuto];
        [self performSelector:@selector(captureImage) withObject:nil afterDelay:_delayTimeForFlash];
    }
    else if(_flashMode == FLASH_MODE_ON && [_stillCamera.inputCamera hasTorch])
    {
        //  ON
        [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeOn];
        [self performSelector:@selector(captureImage) withObject:nil afterDelay:_delayTimeForFlash];
    }
    else
    {
        //  もともと消えてる想定でOFFの指定はしない
        [self captureImage];
    }
}

- (void)captureImage
{
    //  キャプチャー処理
    [_filter prepareForImageCapture];
    
    [_stillCamera capturePhotoAsImageProcessedUpToFilter:_filter withCompletionHandler:^(UIImage *processedImage, NSError *error) {
        
        //  キャプチャー完了処理
        if([_stillCamera.inputCamera hasTorch])
            [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeOff];
        
        [_stillCamera.inputCamera unlockForConfiguration];
        
        //  mainThread
        runOnMainQueueWithoutDeadlocking(^{
            
            //  ビュー類の状態を戻す処理
            [self restartCamera];
            
            //
            if(_autoSaveToCameraroll)
            {
                ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                [library writeImageDataToSavedPhotosAlbum:UIImageJPEGRepresentation(processedImage, 1.0) metadata:nil completionBlock:^(NSURL *assetURL, NSError *error)
                 {
                     if(error)
                     {
                         NSLog(@"ERROR: the image failed to be written");
                     }
                     else
                     {
                         NSLog(@"PHOTO SAVED - assetURL: %@", assetURL);
                     }
                 }];
            }
        });
    }];
}

- (void)restartCamera
{
    _shutterButton.enabled = YES;
    _cameraFrontBackButton.alpha = 1.0;
    _flashButton.alpha = 1.0;
}

#pragma mark - kvo

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"adjustingFocus"])
    {
        BOOL state = _stillCamera.inputCamera.isAdjustingFocus;
        CGPoint pos = _stillCamera.inputCamera.focusPointOfInterest;
        
        if([_stillCamera.inputCamera isFocusPointOfInterestSupported])
            _focusFrameView.center = [self convertToTouchPosFromInterestPoint:pos];
        else
            _focusFrameView.center = CGPointMake(CGRectGetWidth(self.bounds)/2.0, CGRectGetHeight(self.bounds)/2.0);
        
        //
        [UIView animateWithDuration:state?0.0:0.5 delay:0.0 options:0 animations:^{
            _focusFrameView.alpha = state?1.0:0.0;
        } completion:nil];
        
        //  delegate
        if([_delegate respondsToSelector:@selector(cameraView:didChangeAdjustingFocus:devide:)])
        {
            [_delegate cameraView:self didChangeAdjustingFocus:state devide:_stillCamera.inputCamera];
        }
    }
}
@end
