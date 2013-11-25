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
#import "DLCGrayscaleContrastFilter.h"
#import "GPUImageStillCamera+CaptureOrientation.h"
#import "DeviceOrientation.h"
#import "UIImage+Normalize.h"

@interface CameraView ()
{
    NSArray *_filterNameArray;
}
@property (strong, nonatomic) GPUImageStillCamera *stillCamera;
@property (strong, nonatomic) GPUImageOutput<GPUImageInput> *filter;
@property (assign, nonatomic) BOOL hasCamera;
@property (assign, nonatomic) UIDeviceOrientation orientation;
@property (strong, nonatomic) NSString *currentFilterName;

@property (assign, nonatomic) BOOL isFilterChanging;

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
    
    //  Filterを用意
    _filterNameArray = @[ @"normal", @"HiContrast", @"CrossProcess", @"02", @"Grayscale", @"17", @"aqua", @"yellowRed", @"06", @"purpleGreen" ];
    
    _currentFilterName = _filterNameArray[0];
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
            _stillCamera.horizontallyMirrorFrontFacingCamera = YES;
            
            //  forcusの監視をする
            [_stillCamera.inputCamera addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:nil];
            
            //  Deviceの状態を常に監視してみる（ロックの時も）
            [[DeviceOrientation sharedManager] startAccelerometer];

            //  orientationの監視をする
            [[DeviceOrientation sharedManager] addObserver:self forKeyPath:@"orientation" options:NSKeyValueObservingOptionNew context:nil];
            
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
    
    //  orientationの監視をやめる
    [[DeviceOrientation sharedManager] removeObserver:self forKeyPath:@"orientation"];
    
    //  orientationのアップデート止める
    [[DeviceOrientation sharedManager] stopAccelerometer];
    
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
        
        if(self.fillMode == kGPUImageFillModeStretch)
        {
            //  まんま伸ばすのでscaleはそのまま
        }
        else if(self.fillMode == kGPUImageFillModePreserveAspectRatio)
        {
            //  アスペクト守ってフィットなので最小の方
            scaleH = scaleW = MIN(scaleW, scaleH);
        }
        else if(self.fillMode == kGPUImageFillModePreserveAspectRatioAndFill)
        {
            //  アスペクト守って画面はみ出してfillさせるので最大の方
            scaleH = scaleW = MAX(scaleW, scaleH);
        }
        
        width *= scaleW;
        height *= scaleH;
        
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
    
    [_stillCamera captureFixFlipPhotoAsImageProcessedUpToFilter:_filter orientation:_orientation withCompletionHandler:^(UIImage *processedImage, NSError *error) {

        //  キャプチャー完了処理
        if([_stillCamera.inputCamera hasTorch])
            [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeOff];
        
        //  アンロック
        [_stillCamera.inputCamera unlockForConfiguration];
        
        //  回転がおかしくなる時があるので、UIImageを作りなおす
        UIImage *fixImage = [processedImage normalizedImage];

        //  mainThread
        runOnMainQueueWithoutDeadlocking(^{
            
            
            //  delegate
            if([_delegate respondsToSelector:@selector(cameraView:didCapturedImage:)])
            {
                [_delegate cameraView:self didCapturedImage:fixImage];
            }
            
            //
            if(_autoSaveToCameraroll)
            {
                ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                
                [library writeImageDataToSavedPhotosAlbum:UIImageJPEGRepresentation(fixImage, _jpegQuality) metadata:nil completionBlock:^(NSURL *assetURL, NSError *error)
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
            
            //  ビュー類の状態を戻す処理
            [self performSelector:@selector(restartCamera) withObject:nil afterDelay:0.2];
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
    else if([keyPath isEqualToString:@"orientation"])
    {
        if([DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceDown || [DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceUp)
            return;
        
        if(_orientation != [DeviceOrientation sharedManager].orientation)
        {
            _orientation = [DeviceOrientation sharedManager].orientation;
            
            //  UIを回す
            CGAffineTransform transform = CGAffineTransformIdentity;
            
            if(_orientation == UIDeviceOrientationPortrait)
                transform = CGAffineTransformMakeRotation(0.0);
            else if(_orientation == UIDeviceOrientationPortraitUpsideDown)
                transform = CGAffineTransformMakeRotation(M_PI);
            else if(_orientation == UIDeviceOrientationLandscapeLeft)
                transform = CGAffineTransformMakeRotation(M_PI*0.5);
            else if(_orientation == UIDeviceOrientationLandscapeRight)
                transform = CGAffineTransformMakeRotation(M_PI*1.5);
            
            //
            [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
                
                _flashButton.transform = transform;
                _cameraFrontBackButton.transform = transform;
            } completion:nil];
        }
    }
}

#pragma mark - Filter

- (NSArray*)filterNameArray
{
    return _filterNameArray;
}

//  フィルターを選択
- (void)setFilterWithName:(NSString*)name
{
    if(![_filterNameArray containsObject:name])
    {
        //  フィルター名がない
        NSLog(@"error:not exist filter %@", name);
        return;
    }
    
    //
    _currentFilterName = name;

    //  一旦接続を切る
    [self removeAllTargets];
    
    //  フィルターを作る
    NSInteger index = [_filterNameArray indexOfObject:name];
    
    switch (index) {
        case 0:{
            _filter = [[GPUImageFilter alloc] init];
        } break;
            
        case 1:{
            _filter = [[GPUImageContrastFilter alloc] init];
            [(GPUImageContrastFilter *)_filter setContrast:1.75];
        } break;
            
        case 2: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"crossprocess"];
        } break;
            
        case 3: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"02"];
        } break;
            
        case 4: {
            _filter = [[DLCGrayscaleContrastFilter alloc] init];
        } break;
            
        case 5: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"17"];
        } break;
            
        case 6: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"aqua"];
        } break;
            
        case 7: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"yellow-red"];
        } break;
            
        case 8: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"06"];
        } break;
            
        case 9: {
            _filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"purple-green"];
        } break;
            
        default:
            _filter = [[GPUImageFilter alloc] init];
            break;
    }
    
    //  フィルターを設定
    [self prepareFilter];
}

@end
