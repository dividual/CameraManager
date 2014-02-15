//
//  CameraManager.m
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "CameraManager.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "DLCGrayscaleContrastFilter.h"
#import "GPUImageStillCamera+Utility.h"
#import "DeviceOrientation.h"
#import "UIImage+Normalize.h"
#import "NSDate+stringUtility.h"
#import "GPUImageFilter+ProcessSizeUtility.h"
#import <NSObject+EventDispatcher/NSObject+EventDispatcher.h>

@interface CameraManager ()
{
    NSArray *_filterNameArray;
    NSMutableArray *_previewViews;
    NSMutableArray *_focusViews;
    NSMutableArray *_flashButons;
    NSMutableArray *_shutterButtons;
    NSMutableArray *_cameraRotateButtons;
}
@property (strong, nonatomic) GPUImageStillCamera *stillCamera;
@property (strong, nonatomic) GPUImageOutput <GPUImageInput> *filter;
@property (assign, nonatomic) CGFloat maxLevel;

@property (assign, nonatomic) CGSize cameraOutputOriginalSize;
@property (assign, nonatomic) BOOL hasCamera;
@property (assign, nonatomic) UIDeviceOrientation orientation;
@property (strong, nonatomic) NSString *currentFilterName;

@property (assign, nonatomic) BOOL isFilterChanging;
@property (assign, nonatomic) BOOL isCameraRunning;

@property (strong, nonatomic) NSArray *chooseFilterFilters;
@property (strong, nonatomic) NSArray *chooseFilterViews;
@property (strong, nonatomic) UIView *chooseFilterBaseView;
@property (strong, nonatomic) UITapGestureRecognizer *chooseFilterTapGesture;
@property (strong, nonatomic) GPUImageView *chooseFilterPreviewView;

@property (assign, nonatomic) BOOL isChooseFilterMode;
@property (assign, nonatomic) BOOL isCameraOpened;

@property (strong, nonatomic) GPUImageMovieWriter *movieWriter;

@property (strong, nonatomic) NSString *tmpMovieSavePath;
@property (strong, nonatomic) NSTimer *recordingProgressTimer;
@property (strong, nonatomic) NSMutableArray *tmpMovieSavePathArray;    //ここに残ってるというのは、まだ処理に使ってるかもしれないという意味

@property (assign, nonatomic) BOOL focusViewShowHide;
@property (assign, nonatomic) BOOL adjustingFocus;  //  フォーカス中の判定を補正するための
@property (assign, nonatomic) BOOL shutterReserved; //  フォーカス中にShutter押された時用のフラグ

@property (assign, nonatomic) CGSize originalFocusCursorSize;
@end

#pragma mark -

@implementation CameraManager{
	int _currentFilterId;
}

#pragma mark singleton

+ (CameraManager*)sharedManager
{
    static dispatch_once_t pred = 0;
    __strong static id _sharedObject = nil;
    
    dispatch_once(&pred, ^{
        
        _sharedObject = [[CameraManager alloc] init]; // or some other init method
    });
    
    return _sharedObject;
}

#pragma mark -

/// 現在選択中のフィルターIDを取得
-(int)currentFilterId{
	return _currentFilterId;
}

- (void)setup
{
    //  初期化処理
	_currentFilterId = 0;
    
    //  エフェクト用のFilterを設定
    _filter = [[GPUImageFilter alloc] init];
    
    //  デフォルトのフラッシュモード指定しておく
    _flashMode = CMFlashModeOff;
    
    //  デフォルトのdelaytime
    _delayTimeForFlash = 0.25;
    
    //  デフォルトはカメラロール保存自動
    _autoSaveToCameraroll = YES;
    
    //  デフォルトはサイレントモードはOFF
    _silentShutterMode = NO;
    
    //  デフォルトのJpegQuality
    _jpegQuality = 0.9;
    
    //  Filterを用意
    _filterNameArray = @[ @"なし", @"セピア", @"プロセス", @"インスタント", @"グレイスケール", @"17", @"アクア", @"トランスファー", @"オールド" ];
    
    _currentFilterName = _filterNameArray[0];
    
    //  previewViews関連
    _previewViews = [NSMutableArray array];
    
    //  FocusViews
    _focusViews = [NSMutableArray array];
    
    //  flashButtons
    _flashButons = [NSMutableArray array];
    
    //  flashButtons
    _shutterButtons = [NSMutableArray array];
    
    //  flashButtons
    _cameraRotateButtons = [NSMutableArray array];
    
    //  デフォルト動画撮影時間は10秒としておく
    _videoDuration = 10.0;
    
    //
    _tmpMovieSavePathArray = [NSMutableArray array];
}

#pragma mark -

- (void)openCamera
{
    if(_isCameraOpened)
    {
        NSLog( @"カメラはすでにオープンされています" );
        return;
    }
    
    NSLog(@"setUpCamera");
    
    _isCameraOpened = YES;
    
    //
    for(UIView *focuview in _focusViews)
    {
        //  フォーカスのImageViewを消しておく
        focuview.alpha = 0.0;
        
        //  念のためフォーカスのImageViewを最前面にしておく
        [focuview.superview bringSubviewToFront:focuview];
    }
    
    //  バックグラウンドで実行
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        //  カメラが使えるかどうか調べる
        if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
        {
            //  カメラある
            
            //  GPUImageStillCamera作る
            BOOL isRearCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
            
			if( !_sessionPresetForStill )
//				_sessionPresetForStill = AVCaptureSessionPresetPhoto;
				_sessionPresetForStill = AVCaptureSessionPreset1280x720;// ブーストより16:9撮影を優先するため、1280にする
            
            if( !_sessionPresetForVideo)
                _sessionPresetForVideo = AVCaptureSessionPreset1280x720;
            
            if( !_sessionPresetForFrontStill )
				_sessionPresetForFrontStill = AVCaptureSessionPresetPhoto;
            
            if( !_sessionPresetForFrontVideo)
                _sessionPresetForFrontVideo = AVCaptureSessionPresetHigh;
            
            _stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:self.sessionPresetForStill cameraPosition:isRearCameraAvailable?AVCaptureDevicePositionBack:AVCaptureDevicePositionFront];
            
            _stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
            //_stillCamera.horizontallyMirrorFrontFacingCamera = NO;
            
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
                
                [self updateButtons];
                
                //  ゲイン増幅機能ON
                [self setBoostMode:YES];
                
                //  フォーカスを合わせる処理を開始
                [self setFocusPoint:CGPointMake(0.5, 0.5)];
            });
            
            //  notificationの登録
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDeviceSubjectAreaDidChangeNotification:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];
        }
        else
        {
            //  カメラがないときはとりあえずなにもしない
        }
        
    });
}

- (void)closeCamera
{
    if(!_isCameraOpened)
    {
        NSLog( @"すでにカメラは閉じています" );
        return;
    }
    
    if([_stillCamera.captureSession isRunning])
    {
        NSLog(@"closeCamera");
        
        if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
        {
            //  forcusの監視をやめる
            //  エラーがでるのでremoveするのをやめた。オブジェクトが消されるはずだからよしとする
            //[_stillCamera.inputCamera removeObserver:self forKeyPath:@"adjustingFocus"];
            
            //  orientationの監視をやめる
            [[DeviceOrientation sharedManager] removeObserver:self forKeyPath:@"orientation"];
            
            //  orientationのアップデート止める
            [[DeviceOrientation sharedManager] stopAccelerometer];
            
            //
            [_stillCamera stopCameraCapture];
            [self removeAllTargets];
            
            //
            _stillCamera = nil;
        }
    }
    
    _isCameraOpened = NO;
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
    
    _isCameraRunning = YES;
}

- (void)prepareLiveFilter
{
    //  リアルタイム処理のフィルター準備
    [_stillCamera addTarget:_filter];
    
    //  previewViewsにそれぞれつなぐ
    for(GPUImageView *previewView in _previewViews)
        [_filter addTarget:previewView];
    
    //
    [_filter prepareForImageCapture];
}

- (void)removeAllTargets
{
    [_stillCamera removeAllTargets];
    
    //regular filter
    [_filter removeAllTargets];
    
    //
    _isCameraRunning = NO;
}

#pragma mark -

- (id)init
{
    self = [super init];
    if(self)
    {
        [self setup];
    }
    return self;
}

#pragma mark - PreviewViews

- (void)addPreviewView:(GPUImageView*)view
{
    //  previewViewsに追加
    [_previewViews addObject:view];
    
    //
    if(_stillCamera.cameraPosition == AVCaptureDevicePositionFront)
        [view setInputRotation:kGPUImageFlipHorizonal atIndex:0];
    else
        [view setInputRotation:kGPUImageNoRotation atIndex:0];
    
    //
    [_filter addTarget:view];
}

- (void)addPreviewViewsFromArray:(NSArray*)viewsArray
{
    //  previewViewsに追加
    [_previewViews addObjectsFromArray:viewsArray];
    
    for(GPUImageView *view in viewsArray)
        [_filter addTarget:view];
}

- (void)removeAllPreviewViews
{
    //  削除
    [_previewViews removeAllObjects];
    
    for(GPUImageView *view in _previewViews)
        [_filter removeTarget:view];
}

- (void)removePreviewView:(GPUImageView*)view
{
    //  削除
    [_previewViews removeObject:view];
    
    [_filter removeTarget:view];
}

- (NSArray*)previewViews
{
    return _previewViews;
}

#pragma mark - FocusViews

- (void)addFocusView:(UIView*)view
{
    if(CGSizeEqualToSize(_originalFocusCursorSize, CGSizeZero))
    {
        _originalFocusCursorSize = view.bounds.size;
    }
    //  FocusViewsに追加
    [_focusViews addObject:view];
    
    //
    if(!_stillCamera.inputCamera.adjustingFocus)
        view.alpha = 0.0;
}

- (void)addFocusViewsFromArray:(NSArray*)viewsArray
{
    //  FocusViewsに追加
    [_focusViews addObjectsFromArray:viewsArray];
    
    //
    for(UIView *view in viewsArray)
        if(!_stillCamera.inputCamera.adjustingFocus)
            view.alpha = 0.0;
}

- (void)removeAllFocusViews
{
    //  削除
    [_focusViews removeAllObjects];
}

- (void)removeFocusView:(UIView*)view
{
    //  削除
    [_focusViews removeObject:view];
}

- (NSArray*)focusViews
{
    return _focusViews;
}

#pragma mark - FlashButtons

- (void)addFlashButton:(UIButton*)button
{
    button.exclusiveTouch = YES;
    [_flashButons addObject:button];
    [button addTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)addFlashButtonsFromArray:(NSArray*)buttonsArray
{
    [_flashButons addObjectsFromArray:buttonsArray];
    
    for(UIButton *button in buttonsArray)
    {
        button.exclusiveTouch = YES;
        [button addTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)removeAllFlashButtons
{
    for(UIButton *button in _flashButons)
    {
        [button removeTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    [_flashButons removeAllObjects];
}

- (void)removeFlashButton:(UIButton*)button
{
    [button removeTarget:self action:@selector(changeFlashMode:) forControlEvents:UIControlEventTouchUpInside];
    [_flashButons removeObject:button];
}

#pragma mark - ShutterButtons

- (void)addShutterButton:(UIButton*)button
{
    button.exclusiveTouch = YES;
    [_shutterButtons addObject:button];
    [button addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)addShutterButtonsFromArray:(NSArray*)buttonsArray
{
    [_shutterButtons addObjectsFromArray:buttonsArray];
    
    for(UIButton *button in buttonsArray)
    {
        button.exclusiveTouch = YES;
        [button addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)removeAllShutterButtons
{
    for(UIButton *button in _flashButons)
    {
        [button removeTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    [_shutterButtons removeAllObjects];
}

- (void)removeShutterButton:(UIButton*)button
{
    [button removeTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
    [_shutterButtons removeObject:button];
}

#pragma mark - CameraRotateButtons

- (void)addCameraRotateButton:(UIButton*)button
{
    button.exclusiveTouch = YES;
    [_cameraRotateButtons addObject:button];
    [button addTarget:self action:@selector(rotateCameraPosition:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)addCameraRotateButtonsFromArray:(NSArray*)buttonsArray
{
    [_cameraRotateButtons addObjectsFromArray:buttonsArray];
    
    for(UIButton *button in buttonsArray)
    {
        button.exclusiveTouch = YES;
        [button addTarget:self action:@selector(rotateCameraPosition:) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)removeAllCameraRotateButtons
{
    for(UIButton *button in _flashButons)
    {
        [button removeTarget:self action:@selector(rotateCameraPosition:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    [_cameraRotateButtons removeAllObjects];
}

- (void)removeCameraRotateButton:(UIButton*)button
{
    [button removeTarget:self action:@selector(rotateCameraPosition:) forControlEvents:UIControlEventTouchUpInside];
    [_cameraRotateButtons removeObject:button];
}

#pragma mark -

- (void)updateButtons
{
    //  フラッシュがないときは表示消す
    if(![_stillCamera.inputCamera hasTorch])
    {
        for(UIButton *button in _flashButons)
            button.hidden = YES;
    }
    else
    {
        for(UIButton *button in _flashButons)
            button.hidden = NO;
    }
    
    //  フロントカメラ、もしくはリアカメラのみの場合にrotateアイコン消す
    BOOL isFrontCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
    BOOL isRearCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
    if(!isFrontCameraAvailable || !isRearCameraAvailable)
    {
        for(UIButton *button in _cameraRotateButtons)
            button.hidden = YES;
    }
}

#pragma mark -

- (CGRect)inputImageRectInView:(GPUImageView*)view
{
    //  GPUImageViewに表示してる元画像のサイズ
    NSValue *inputSizeValue = [view valueForKey:@"inputImageSize"]; //TODO: ここはちょっと強引なので注意
    if(inputSizeValue)
    {
        CGSize inputSize = [inputSizeValue CGSizeValue];
        
        CGFloat width = inputSize.width;
        CGFloat height = inputSize.height;
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat viewHeight = CGRectGetHeight(view.bounds);
        
        CGFloat scaleW = viewWidth/width;
        CGFloat scaleH = viewHeight/height;
        
        if(view.fillMode == kGPUImageFillModeStretch)
        {
            //  まんま伸ばすのでscaleはそのまま
        }
        else if(view.fillMode == kGPUImageFillModePreserveAspectRatio)
        {
            //  アスペクト守ってフィットなので最小の方
            scaleH = scaleW = MIN(scaleW, scaleH);
        }
        else if(view.fillMode == kGPUImageFillModePreserveAspectRatioAndFill)
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
    
    return view.bounds;
}

- (CGPoint)convertToInterestPointFromTouchPos:(CGPoint)pos inView:(GPUImageView*)view
{
    CGRect inputRect = [self inputImageRectInView:view];
    
    CGPoint fixPos = CGPointMake(pos.x-inputRect.origin.x, pos.y-inputRect.origin.y);
    
    CGFloat xx = fixPos.x/CGRectGetWidth(inputRect);
    CGFloat yy = fixPos.y/CGRectGetHeight(inputRect);
    
    return CGPointMake(yy, 1.0-xx);
}

- (CGPoint)convertToTouchPosFromInterestPoint:(CGPoint)pos inView:(GPUImageView*)view
{
    CGRect inputRect = [self inputImageRectInView:view];
    
    pos = CGPointMake(1.0-pos.y, pos.x);
    
    CGPoint fixPos = CGPointMake(pos.x*CGRectGetWidth(inputRect) + inputRect.origin.x, pos.y*CGRectGetHeight(inputRect) + inputRect.origin.y);
    
    return fixPos;
}

#pragma mark -

- (void)setFocusPoint:(CGPoint)pos inView:(GPUImageView*)view
{
    if(!CGRectContainsPoint(view.bounds, pos))
        return;
    
    //
    CGSize frameSize = view.frame.size;
    
    if ([_stillCamera cameraPosition] == AVCaptureDevicePositionFront)
    {
        //  前のカメラでプレビューするときは左右反対になる
        pos.x = frameSize.width - pos.x;
    }
    
    //  座標変換
    CGPoint pointOfInterest = [self convertToInterestPointFromTouchPos:pos inView:view];
    
    //
    [self setFocusPoint:pointOfInterest];
}

- (void)setBoostMode:(BOOL)enabled
{
    AVCaptureDevice *device = _stillCamera.inputCamera;
    
    
    //  ブーストモードに対応してたら設定しておく
    if(device.isLowLightBoostSupported)
    {
        NSError *error;
        if([device lockForConfiguration:&error])    //  devicelock
        {
            device.automaticallyEnablesLowLightBoostWhenAvailable = enabled;
            [device unlockForConfiguration];
        }
    }
}
- (void)setFocusPoint:(CGPoint)pos
{
    //
    AVCaptureDevice *device = _stillCamera.inputCamera;
    
    //  タッチした位置へのフォーカスをサポートするかチェック
    if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus])
    {
        _adjustingFocus = YES;
        
        NSError *error;
        if([device lockForConfiguration:&error])    //  devicelock
        {
            //  画面の変化をチェックする
            [device setSubjectAreaChangeMonitoringEnabled:YES];
            
            //  フォーカスを合わせる位置を指定
            [device setFocusPointOfInterest:pos];
            [device setFocusMode:AVCaptureFocusModeAutoFocus];
            
            //  アニメーションスタート
            [self showFocusCursorWithPos:pos];
            
            //
            if(device.smoothAutoFocusSupported)
                device.smoothAutoFocusEnabled = NO;
            
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            {
                [device setExposurePointOfInterest:pos];
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            }
            
            if([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
            {
                [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
            }
            
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"ERROR = %@", error);
        }
    }
}

- (void)setFocusModeContinousAutoFocus
{
    AVCaptureDevice *device = _stillCamera.inputCamera;
    
    if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
    {
        NSError *error;
        if([device lockForConfiguration:&error])    //  devicelock
        {
            [device setFocusPointOfInterest:CGPointMake(0.5, 0.5)];
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            
            //  画面の変化を追うのをやめる
            [device setSubjectAreaChangeMonitoringEnabled:NO];
        }
        [device unlockForConfiguration];
    }
}

- (void)setFlashMode:(CMFlashMode)flashMode
{
    _flashMode = flashMode;
    
    //
    NSString *imgName = nil;
    switch(_flashMode)
    {
        case CMFlashModeAuto:
            imgName = _flashAutoImageName;
            break;
            
        case CMFlashModeOff:
            imgName = _flashOffmageName;
            break;
            
        case CMFlashModeOn:
            imgName = _flashOnImageName;
            break;
    }
    
    if(imgName)
    {
        UIImage *img = [UIImage imageNamed:imgName];
        if(img)
        {
            for(UIButton *button in _flashButons)
                [button setImage:img forState:UIControlStateNormal];
        }
    }
}

#pragma mark - IBAction

- (void)changeFlashMode:(id)sender
{
    //  flashモードのボタンを押された
    self.flashMode = (_flashMode+1)%3;
}


///  シャッターボタンを押された
- (void)takePhoto:(id)sender
{
    if( [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera] == NO ){
		// カメラが無ければ処理中断
		return;
	}
	
    //  フォーカスに対応してないとき用の処理
    if(!_stillCamera.inputCamera.isFocusPointOfInterestSupported)
        _adjustingFocus = NO;
    
    //  フォーカスを合わせてる途中だったら
    if(_adjustingFocus)
    {
        _shutterReserved = YES;
    }
    else
        _shutterReserved = NO;
    
    //
    if(_cameraMode == CMCameraModeStill)
    {
        //  静止画撮影
        for(UIButton *button in _shutterButtons)
            button.enabled = NO;
        
        for(UIButton *button in _cameraRotateButtons)
            button.alpha = 0.0;
        
        for(UIButton *button in _flashButons)
            button.alpha = 0.0;
        
        if(_shutterReserved)
            return;
        
        if (_hasCamera)
        {
            [self prepareForCapture];
        }
    }
    else
    {
        if(_shutterReserved)
            return;
        
        //  動画撮影
        [self startVideoRec];
    }
}

//
- (void)rotateCameraPosition:(id)sender
{
    //  ボタンを非アクティブに（連打防止）
    for(UIButton *button in _cameraRotateButtons)
        button.enabled = NO;
    
    //  現在のカメラポジションを見て、解像度の切り替え考える
    if (_stillCamera.inputCamera.position == AVCaptureDevicePositionBack)
    {
        //  前のカメラに変えるってことなので、解像度設定をPhotoに
        if(_cameraMode == CMCameraModeStill)
        {
            [_stillCamera rotateCameraWithCaptureSessionPreset:_sessionPresetForFrontStill];
        }
        else
        {
            [_stillCamera rotateCameraWithCaptureSessionPreset:_sessionPresetForFrontVideo];
        }
    }
    else
    {
        //  後ろのカメラに設定するときは、解像度を動画か静止画かで切り替える
        if(_cameraMode == CMCameraModeStill)
        {
            [_stillCamera rotateCameraWithCaptureSessionPreset:_sessionPresetForStill];
        }
        else
        {
            [_stillCamera rotateCameraWithCaptureSessionPreset:_sessionPresetForVideo];
        }
    }
    
    //  ボタンをアクティブに
    for(UIButton *button in _cameraRotateButtons)
        button.enabled = YES;
    
    //  フラッシュの有り無しに応じてGUIの表示/非表示、フロントモードの時は左右入れ替えてプレビュー
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera] && _stillCamera)
    {
        if ([_stillCamera.inputCamera hasFlash] && [_stillCamera.inputCamera hasTorch])
        {
            for(UIButton *button in _flashButons)
                button.hidden = NO;
        }
        else
        {
            for(UIButton *button in _flashButons)
                button.hidden = YES;
        }
        
        //
        if(_stillCamera.cameraPosition == AVCaptureDevicePositionFront)
        {
            for(GPUImageView *view in _previewViews)
            {
                [view setInputRotation:kGPUImageFlipHorizonal atIndex:0];
            }
        }
        else
        {
            for(GPUImageView *view in _previewViews)
            {
                [view setInputRotation:kGPUImageNoRotation atIndex:0];
            }
        }
    }
}

#pragma mark - capture

- (void)prepareForCapture
{
    //  ロック
    [_stillCamera.inputCamera lockForConfiguration:nil];
    
    //  フラッシュの準備（上記のロックをかけてからでないと処理できないっぽい）
    if(_flashMode == CMFlashModeAuto && [_stillCamera.inputCamera hasTorch])
    {
        //  自動
        [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeAuto];
        [self performSelector:@selector(captureImage) withObject:nil afterDelay:_delayTimeForFlash];
    }
    else if(_flashMode == CMFlashModeOn && [_stillCamera.inputCamera hasTorch])
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
    
    __block UIImage *originalImage = nil;
    
    //  撮影後の処理をブロックで
    void (^completion)(UIImage *processedImage, UIImage *imageForAnimation, NSError *error) = ^(UIImage *processedImage, UIImage *imageForAnimation, NSError *error){
        
        //  キャプチャー完了処理
        if([_stillCamera.inputCamera hasTorch])
            [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeOff];
        
        //  アンロック
        [_stillCamera.inputCamera unlockForConfiguration];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            //  delegate
            if([_delegate respondsToSelector:@selector(cameraManager:didPlayShutterSoundWithImage:)])
            {
                [_delegate cameraManager:self didPlayShutterSoundWithImage:imageForAnimation];
            }
        });
        
        //
        originalImage = processedImage;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            //  回転がおかしくなる時があるので、UIImageを作りなおす
            UIImage *fixImage = [originalImage normalizedImage];
            originalImage = nil;
            
            //  mainThread
            dispatch_async(dispatch_get_main_queue(), ^{
                
                //  delegate
                if([_delegate respondsToSelector:@selector(cameraManager:didCapturedImage:)])
                {
                    [_delegate cameraManager:self didCapturedImage:fixImage];
                }
                
                //
                if(_autoSaveToCameraroll)
                {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        
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
                    });
                }
                
                //  ビュー類の状態を戻す処理
                [self performSelector:@selector(restartCamera) withObject:nil afterDelay:0.2];
            });
        });
    };
    
    if(_silentShutterMode)
    {
        //  サイレントモードの時は別処理
        [self captureImageSilentWithCompletion:^(UIImage *processedImage, UIImage *imageForAnimation, NSError *error) {
            
            UIImage *fixImage = [imageForAnimation normalizedImage];
            completion(processedImage, fixImage, error);
        }];
    }
    else
    {
        UIImage *imgForAnimation = [_filter imageFromCurrentlyProcessedOutputWithOrientation:UIImageOrientationUp];
        UIImage *fixImage = [imgForAnimation normalizedImage];
        
        [_filter prepareForImageCapture];
        
        //  通常の撮影
        [_stillCamera captureFixFlipPhotoAsImageProcessedUpToFilter:_filter orientation:_orientation withCompletionHandler:^(UIImage *processedImage, NSError *error) {
            //
            completion(processedImage, fixImage, error);
        }];
    }
}

- (UIImage*)imageFromCurrentlyProcessedOutputFixFlipWithOrientation:(UIDeviceOrientation)orientation stillCamera:(GPUImageStillCamera*)stillCamera
{
    UIImageOrientation imageOrientation = UIImageOrientationLeft;
    
    BOOL isFlipped = stillCamera.cameraPosition == AVCaptureDevicePositionFront && stillCamera.horizontallyMirrorFrontFacingCamera?YES:NO;
    
	switch(orientation)
    {
		case UIDeviceOrientationPortrait:
            imageOrientation = isFlipped?UIImageOrientationUpMirrored:UIImageOrientationUp;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            imageOrientation = isFlipped?UIImageOrientationDownMirrored:UIImageOrientationDown;
            break;
        case UIDeviceOrientationLandscapeLeft:
            imageOrientation = isFlipped?UIImageOrientationRightMirrored:UIImageOrientationLeft;
            break;
        case UIDeviceOrientationLandscapeRight:
            imageOrientation = isFlipped?UIImageOrientationLeftMirrored:UIImageOrientationRight;
            break;
        default:
            imageOrientation = isFlipped?UIImageOrientationUpMirrored:UIImageOrientationUp;
            break;
	}
    
    UIImage *image = [_filter imageFromCurrentlyProcessedOutputWithOrientation:imageOrientation];
    
    return image;
}

- (void)captureImageSilentWithCompletion:(void(^)(UIImage *processedImage, UIImage *imageForAnimation, NSError *error))compBlock
{
    UIImage *img = [self imageFromCurrentlyProcessedOutputFixFlipWithOrientation:_orientation stillCamera:_stillCamera];
    UIImage *imageForAnimation = [UIImage imageWithCGImage:img.CGImage scale:1.0 orientation:UIImageOrientationUp];
    
    compBlock(img, imageForAnimation, nil);
}

- (void)restartCamera
{
    for(UIButton *button in _shutterButtons)
        button.enabled = YES;
    
    for(UIButton *button in _cameraRotateButtons)
        button.alpha = 1.0;
    
    for(UIButton *button in _flashButons)
        button.alpha = 1.0;
}

#pragma mark - video

- (CGAffineTransform)videoOrientation
{
    CGAffineTransform transform = CGAffineTransformMakeRotation(0.0);
    
    BOOL isFront = _stillCamera.cameraPosition == AVCaptureDevicePositionFront?YES:NO;
    
    //
	switch(_orientation)
    {
		case UIDeviceOrientationPortrait:
            transform = CGAffineTransformRotate(transform, 0.0);
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
        case UIDeviceOrientationLandscapeLeft:
            transform = CGAffineTransformRotate(transform, isFront?M_PI_2:(M_PI+M_PI_2));
            break;
        case UIDeviceOrientationLandscapeRight:
            transform = CGAffineTransformRotate(transform, isFront?(M_PI+M_PI_2):M_PI_2);
            break;
        default:
            transform = CGAffineTransformRotate(transform, 0.0);
            break;
	}
    
    return transform;
}

- (CGSize)videoSize
{
    if([_sessionPresetForVideo isEqualToString:AVCaptureSessionPreset1920x1080])
    {
        return CGSizeMake(1080.0, 1920.0);
    }
    else if([_sessionPresetForVideo isEqualToString:AVCaptureSessionPreset1280x720])
    {
        return CGSizeMake(720.0, 1280.0);
    }
    else if([_sessionPresetForVideo isEqualToString:AVCaptureSessionPreset640x480])
    {
        return CGSizeMake(480.0, 640.0);
    }
    else if([_sessionPresetForVideo isEqualToString:AVCaptureSessionPreset352x288])
    {
        return CGSizeMake(288.0, 352.0);
    }
    
    //  GPUImageViewに表示してる元画像のサイズ
    return ((GPUImageFilter*)_filter).outputFrameSize;
}

- (void)showHideVideoRecording:(BOOL)state
{
    //
    if(!state)
    {
        //  シャッターボタンを録画中の停止ボタンに変える
        [self changeShutterButtonImageTo:_videoStopButtonImageName];
    }
    else
    {
        //  シャッターボタンをビデオモードの録画開始ボタンに変える
        [self changeShutterButtonImageTo:_videoShutterButtonImageName];
    }
    
    for(UIButton *button in _cameraRotateButtons)
        button.alpha = state?1.0:0.0;
    
    for(UIButton *button in _flashButons)
        button.alpha = state?1.0:0.0;
}

- (void)setupTorch
{
    if([_stillCamera.inputCamera hasTorch])
    {
        //  フラッシュの設定
        NSError *error = nil;
        if (![_stillCamera.inputCamera lockForConfiguration:&error])
        {
            NSLog(@"Error locking for configuration: %@", error);
        }
        
        //  フラッシュの準備（上記のロックをかけてからでないと処理できないっぽい）
        if(_flashMode == CMFlashModeAuto && [_stillCamera.inputCamera hasTorch])
        {
            //  自動
            [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeAuto];
        }
        else if(_flashMode == CMFlashModeOn && [_stillCamera.inputCamera hasTorch])
        {
            //  ON
            [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeOn];
        }
        else
        {
            //  もともと消えてる想定でOFFの指定はしない
        }
        
        [_stillCamera.inputCamera unlockForConfiguration];
    }
}

- (void)offTorch
{
    if([_stillCamera.inputCamera hasTorch])
    {
        [_stillCamera.inputCamera lockForConfiguration:nil];
        [_stillCamera.inputCamera setTorchMode:AVCaptureTorchModeOff];
        [_stillCamera.inputCamera unlockForConfiguration];
    }
}

- (NSString*)makeTempMovieFileName
{
    NSString *uuidString = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:@"%@.m4v", uuidString];
}

- (void)startVideoRec
{
    //  録画中に押された場合は停止処理する
    if(_recordingProgressTimer)
    {
        [self stopVideoRec];
        return;
    }
    
    //  撮影中に操作できないようにボタン類を消す
    [self showHideVideoRecording:NO];
    
    //  動画撮影開始
    NSString *fileName = [self makeTempMovieFileName];
    _tmpMovieSavePath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp/%@", fileName]];    //アプリがアクティブ中は勝手には消されないので、自分で消す必要あり
    unlink([_tmpMovieSavePath UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    
    //  arrayに追加しておく
    [_tmpMovieSavePathArray addObject:_tmpMovieSavePath];
    
    //  URL
    NSURL *movieURL = [NSURL fileURLWithPath:_tmpMovieSavePath];
    
    //
    _movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:movieURL size:[self videoSize]];
    
    [_filter addTarget:_movieWriter];
    
    //  撮影直前のデリゲート
    if([_delegate respondsToSelector:@selector(cameraManagerWillStartRecordVideo:)])
    {
        [_delegate cameraManagerWillStartRecordVideo:self];
    }
    
    //  音の設定
    _stillCamera.audioEncodingTarget = _movieWriter;
    
    //  フラッシュのセットアップ
    [self setupTorch];
    
    //  遅延時間（オートフォーカスが動き出すので、それが収まったあたりを狙って開始するため固定の遅延）
    double delayToStartRecording = 0.5;
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, delayToStartRecording * NSEC_PER_SEC);
    dispatch_after(startTime, dispatch_get_main_queue(), ^(void){
        
        //  向きの設定をして録画スタート
        [_movieWriter startRecordingInOrientation:[self videoOrientation]];
        
        //  タイマースタート
        [self startRecordingProgressTimer];
    });
}

- (void)startRecordingProgressTimer
{
    if(_recordingProgressTimer)
        [self stopRecordingProgressTimer];
    
    _recordingProgressTimer = [NSTimer timerWithTimeInterval:1.0/10.0 target:self selector:@selector(doProgressRecording:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_recordingProgressTimer forMode:NSRunLoopCommonModes];
}

- (void)stopRecordingProgressTimer
{
    if(_recordingProgressTimer)
    {
        [_recordingProgressTimer invalidate];
        _recordingProgressTimer = nil;
    }
}

- (void)doProgressRecording:(NSTimer*)timer
{
    if(_recordingProgressTimer == timer)
    {
        //  残り時間のチェック
        if(self.remainRecordTime<0.0)
        {
            //  終了
            [self stopVideoRec];
        }
        else
        {
            //  プログレスのデリゲート
            if([_delegate respondsToSelector:@selector(cameraManager:recordingTime:remainTime:)])
            {
                [_delegate cameraManager:self recordingTime:self.recordedTime remainTime:self.remainRecordTime];
            }
        }
    }
}

- (void)stopVideoRec
{
    //  プログレスのタイマー止める
    [self stopRecordingProgressTimer];
    
    //  movieWriteをtargetから消す
    [_filter removeTarget:_movieWriter];
    _stillCamera.audioEncodingTarget = nil;
    [_movieWriter finishRecording];
    NSLog(@"Movie completed");
    
    //  照明必ず消す
    [self offTorch];
    
    //  GUIを元に戻す
    [self showHideVideoRecording:YES];
    
    //  カメラロールに保存してみる
    if(_autoSaveToCameraroll && UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(_tmpMovieSavePath))
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UISaveVideoAtPathToSavedPhotosAlbum(_tmpMovieSavePath, self, @selector(video:didFinishSavingWithError:contextInfo:), nil);
        });
    }
    
    //  撮影完了時のデリゲート
    if([_delegate respondsToSelector:@selector(cameraManager:didRecordMovie:)])
    {
        [_delegate cameraManager:self didRecordMovie:[NSURL fileURLWithPath:_tmpMovieSavePath]];
    }
}

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    NSLog(@"saveVideo to CameraRoll Finished:%@", videoPath);
    
    if([_tmpMovieSavePathArray containsObject:videoPath])
    {
        //  まだ消してはいけない
        //  リストからは消しておく
        [_tmpMovieSavePathArray removeObject:videoPath];
    }
    else
    {
        //  もう処理が終わってるらしいので消す
        [[NSFileManager defaultManager] removeItemAtPath:videoPath error:nil];
        
        NSLog(@"removeFile:%@", videoPath);
    }
}

//  tmpFileはもういらないよの通知
- (void)removeTempMovieFile:(NSURL*)tmpURL
{
    NSString *path = tmpURL.path;
    //
    if([_tmpMovieSavePathArray containsObject:path])
    {
        //  まだ消してはいけない
        //  リストからは消しておく
        [_tmpMovieSavePathArray removeObject:path];
    }
    else
    {
        //  もう処理が終わってるらしいので消す
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        
        NSLog(@"removeFile:%@", path);
    }
}

//
- (NSTimeInterval)recordedTime
{
    CMTime time = _movieWriter.duration;
    
    return CMTimeGetSeconds(time);
}

- (NSTimeInterval)remainRecordTime
{
    return _videoDuration - self.recordedTime;
}

#pragma mark - kvo

- (void)showFocusCursorWithPos:(CGPoint)pos
{
    _focusViewShowHide = YES;
    
    for(UIView *focusView in _focusViews)
    {
        CGPoint focusPos;
        GPUImageView *previewView = (GPUImageView*)focusView.superview;
        if([_stillCamera.inputCamera isFocusPointOfInterestSupported])
        {
            focusPos = [self convertToTouchPosFromInterestPoint:pos inView:previewView];
            
            if(isnan(focusPos.x) || isnan(focusPos.y) || !CGRectContainsPoint(previewView.frame, focusPos))
            {
                //  なんかデータがおかしい時は中心にfocus表示しとく
                focusPos = CGPointMake(CGRectGetWidth(previewView.bounds)/2.0, CGRectGetHeight(previewView.bounds)/2.0);
            }
        }
        else
            focusPos = CGPointMake(CGRectGetWidth(previewView.bounds)/2.0, CGRectGetHeight(previewView.bounds)/2.0);
        
        //  フォーカスが出てくるアニメーション
        focusView.bounds = CGRectMake(0.0, 0.0, _originalFocusCursorSize.width*4.0, _originalFocusCursorSize.height*4.0);
        focusView.center = focusPos;
        
        //
        [focusView.layer removeAllAnimations];
        focusView.alpha = 0.0;
        
        [UIView animateWithDuration:0.1 delay:0.0 options:7<<16 animations:^{
            //
            focusView.bounds = CGRectMake(0.0, 0.0, _originalFocusCursorSize.width, _originalFocusCursorSize.height);
            focusView.center = focusPos;
            
            //
            focusView.alpha = 1.0;
            
        } completion:^(BOOL finished) {
            //
            if(finished)
            {
                focusView.alpha = 1.0;
                [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse animations:^{
                    //
                    focusView.alpha = 0.3;
                    
                } completion:^(BOOL finished) {
                    //
                }];
            }
        }];
    }
}

- (void)hideFocusCursor
{
    for(UIView *focusView in _focusViews)
    {
        [focusView.layer removeAllAnimations];
        
        [UIView animateWithDuration:0.5 delay:0.0 options:0 animations:^{
            //
            focusView.alpha = 0.0;
        } completion:^(BOOL finished) {
            
            if(finished)
                _focusViewShowHide = NO;
        }];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"adjustingFocus"])
    {
        BOOL state = _stillCamera.inputCamera.isAdjustingFocus;
        
        //  カーソルを消すとか表示するとか
        if(state == NO)
            [self hideFocusCursor];
        else if(_focusViewShowHide == NO)
        {
            //  フォーカス開始で、かつfocusViewが表示されてない場合
            CGPoint focusPos;
            if(_stillCamera.inputCamera.focusPointOfInterestSupported)
                focusPos = _stillCamera.inputCamera.focusPointOfInterest;
            else
                focusPos = CGPointMake(0.5, 0.5);
            
            [self showFocusCursorWithPos:focusPos];
        }
        
        //NSLog(@"state=%d , _focusViewShowHide=%d", state, _focusViewShowHide);
        
        //  delegate
        if([_delegate respondsToSelector:@selector(cameraManager:didChangeAdjustingFocus:devide:)])
        {
            [_delegate cameraManager:self didChangeAdjustingFocus:state devide:_stillCamera.inputCamera];
        }
        
        //
        if(_shutterReserved && state == NO)
        {
            _adjustingFocus = NO;
            [self takePhoto:nil];
            _shutterReserved = NO;
        }
        else
        {
            _adjustingFocus = state;
        }
    }
    else if([keyPath isEqualToString:@"orientation"])
    {
        if([DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceDown || [DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceUp)
            return;
        
        if(_orientation != [DeviceOrientation sharedManager].orientation)
        {
            _orientation = [DeviceOrientation sharedManager].orientation;
            
            //  delegate
            if([_delegate respondsToSelector:@selector(cameraManager:didChangeDeviceOrientation:)])
            {
                [_delegate cameraManager:self didChangeDeviceOrientation:_orientation];
            }
        }
    }
}

#pragma mark - Filter

- (NSArray*)filterNameArray
{
    return _filterNameArray;
}

- (GPUImageFilter*)filterWithName:(NSString*)name
{
    //  filterを作って返す
    NSInteger index = [_filterNameArray indexOfObject:name];
    
    GPUImageFilter *filter = nil;
    
    switch (index) {
        case 0:{
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"default"];
        } break;
            
        case 1:{
            filter = [[GPUImageSepiaFilter alloc] init];
        } break;
            
        case 2: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"crossprocess"];
        } break;
            
        case 3: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"02"];
        } break;
            
        case 4: {
            filter = [[DLCGrayscaleContrastFilter alloc] init];
        } break;
            
        case 5: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"17"];
        } break;
            
        case 6: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"aqua"];
        } break;
            
        case 7: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"yellow-red"];
        } break;
            
        case 8: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"06"];
        } break;
            
        default:
            filter = [[GPUImageFilter alloc] init];
            break;
    }
    
    return filter;
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
    
    //
    _filter = [self filterWithName:_currentFilterName];
    
    //  フィルターを設定
    [self prepareFilter];
}

- (void)setFilterWithFilter:(GPUImageFilter*)filter name:(NSString*)name size:(CGSize)originalSize
{
    for(GPUImageView *view in _previewViews)
        [_filter removeTarget:view];
    
    [_stillCamera removeTarget:_filter];
    
    _currentFilterName = name;
    _filter = filter;
    
    [_filter forceProcessingAtSize:originalSize];
    
    for(GPUImageView *view in _previewViews)
    {
        [_filter addTarget:view];
    }
}

//  プレビューに使ってる画像を即座に返す
- (UIImage*)captureCurrentPreviewImage
{
    UIImage *img = [_filter imageFromCurrentlyProcessedOutputWithOrientation:UIImageOrientationUp];
    
    return [img normalizedImage];
}

//  エフェクト一覧の時にフィルター名を表示するときの文字の属性を指定したattributedstringを返す
- (NSAttributedString*)filterNameAttStringWithString:(NSString*)string
{
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    
    //
    NSAttributedString *repString = [[NSAttributedString alloc] initWithString:string attributes:@{ NSFontAttributeName:[UIFont boldSystemFontOfSize:12.0],
                                                                                                    NSForegroundColorAttributeName:[UIColor whiteColor],
                                                                                                    NSParagraphStyleAttributeName:paragraphStyle}];
    
    return repString;
}

//  エフェクト一覧画面を表示するための画面を作る（指定するGPUImageViewはprevieViewsとして追加済みでないとダメ）
- (void)showChooseEffectInPreviewView:(GPUImageView*)previewView
{
    if(_isChooseFilterMode)
        return;
    
    if(![_previewViews containsObject:previewView])
    {
        NSLog(@"error:指定されたviewがpreviewViewsに入ってません。");
        return;
    }
    
    //
    _chooseFilterPreviewView = previewView;
    
    //  Shutterなどを消す
    [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
        //
        for(UIView *view in _previewViews)
        {
            if(view != previewView)
                view.alpha = 0.0;
        }
        for(UIView *view in _shutterButtons)
            view.alpha = 0.0;
        
        for(UIView *view in _cameraRotateButtons)
            view.alpha = 0.0;
        
        for(UIView *view in _flashButons)
            view.alpha = 0.0;
        
    } completion:nil];
    
    
    //  表示するUIViewを作る
    UIView *baseView = [[UIView alloc] initWithFrame:previewView.frame];
    
    //  9つのGPUImageViewを作る（とりあえず配置してみる）
    CGFloat width = CGRectGetWidth(previewView.frame);
    CGFloat height = CGRectGetHeight(previewView.frame);
    
    CGFloat oneWidth = width/3.0;
    CGFloat oneHeight = height/3.0;
    
    int filterNum = MAX(_filterNameArray.count, 9); //9個最大
    
    NSMutableArray *filters = [NSMutableArray array];
    NSMutableArray *views = [NSMutableArray array];
    
    //
    CGSize originalSize = ((GPUImageFilter*)_filter).outputFrameSize;
    
    //
    for(int i=0;i<filterNum;i++)
    {
        int x = i%3;
        int y = i/3;
        
        //  フレーム指定
        CGRect frame = CGRectMake(x*oneWidth, y*oneHeight, oneWidth, oneHeight);
        
        //  ライブフィルタープレビューのviewを作る
        GPUImageView *view = [[GPUImageView alloc] initWithFrame:frame];
        
        //  フィルモード指定
        view.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
        
        //  フィルター指定
        GPUImageFilter *filter = [self filterWithName:_filterNameArray[i]];
        
        //  フィルターの解像度下げる
        [filter forceProcessingAtSizeFixAspect:CGSizeMake(oneWidth, oneHeight) originalSize:originalSize scale:[UIScreen mainScreen].scale];
        
        //  フィルター追加
        [_stillCamera addTarget:filter];
        [filter addTarget:view];
        
        [filters addObject:filter];
        [views addObject:view];
        
        //  フィルター名を追加
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, CGRectGetHeight(frame)-20.0, CGRectGetWidth(frame), 20.0)];
        label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.3];
        label.attributedText = [self filterNameAttStringWithString:_filterNameArray[i]];
        [view addSubview:label];
        label.alpha = 0.0;
        
        //  ベースに追加
        [baseView addSubview:view];
        
        //
        [filter prepareForImageCapture];
    }
    
    //  現在のpreviewを止める
    previewView.enabled = NO;
    
    //  後々消したりするために保持しとく
    _chooseFilterFilters = filters;
    _chooseFilterViews = views;
    _chooseFilterBaseView = baseView;
    
    //  baseViewを画面に追加してみる
    [previewView insertSubview:baseView atIndex:0];
    
    //  animationを実装してみる
    //  とりあえず該当するviewだけアニメーションさせてみる
    NSInteger curFilterIndex = [_filterNameArray indexOfObject:_currentFilterName];
    
    //
    GPUImageView *curView = views[curFilterIndex];
    CGRect toFrame = curView.frame;
    curView.frame = baseView.bounds;
    
    [baseView bringSubviewToFront:curView];
    
    //
    [UIView animateWithDuration:0.3 delay:0.1 options:0 animations:^{
        //
        curView.frame = toFrame;
        
    } completion:^(BOOL finished) {
        //
        //  label表示
        [UIView animateWithDuration:0.2 animations:^{
            for(UIView *view in _chooseFilterBaseView.subviews)
            {
                for(UILabel *label in view.subviews)
                {
                    if([label isKindOfClass:[UILabel class]])
                        label.alpha = 1.0;
                }
            }
        }];
    }];
    
    //  フラグたてる
    _isChooseFilterMode = YES;
    
    //  タッチイベント処理を追加
    _chooseFilterTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleChooseFilterTapGesture:)];
    [baseView addGestureRecognizer:_chooseFilterTapGesture];
}

- (void)handleChooseFilterTapGesture:(UITapGestureRecognizer*)tapGesture
{
    if(tapGesture != _chooseFilterTapGesture)
        return;
    
    CGPoint tapPos = [tapGesture locationInView:_chooseFilterBaseView];
    
    GPUImageView *tapView = nil;
    
    for(GPUImageView *view in _chooseFilterViews)
    {
        if(CGRectContainsPoint(view.frame, tapPos))
        {
            tapView = view;
            break;
        }
    }
    
    //  選択されたfilterの名前割り出す
    NSInteger tapFilterIndex = [_chooseFilterViews indexOfObject:tapView];
    NSString *tapFilterName = _filterNameArray[tapFilterIndex];
    
    //
    [self handleFinishChooseFilterWithFilterName:tapFilterName];
}

- (void)handleFinishChooseFilterWithFilterName:(NSString*)filterName
{
	[self dispatchEvent:@"filterSelected" userInfo:@{@"filterName":filterName}];
    NSInteger index = [_filterNameArray indexOfObject:filterName];
	_currentFilterId = index;
    
    GPUImageView *tapView = _chooseFilterViews[index];
    GPUImageFilter *tapFilter = _chooseFilterFilters[index];
    
    //  選択されたviewを最前面に
    [_chooseFilterBaseView bringSubviewToFront:tapView];
    
    //  label消す
    [UIView animateWithDuration:0.1 animations:^{
        for(UIView *view in _chooseFilterBaseView.subviews)
        {
            for(UILabel *label in view.subviews)
            {
                if([label isKindOfClass:[UILabel class]])
                {
                    label.alpha = 0.0;
                    [label removeFromSuperview];
                }
            }
        }
    }];
    
    //  アニメーションさせる
    [UIView animateWithDuration:0.3 delay:0.1 options:0 animations:^{
        //  選ばれたviewを最大化
        tapView.frame = _chooseFilterBaseView.frame;
        
    } completion:^(BOOL finished) {
        
        //  choose系を消す
        [_chooseFilterBaseView removeGestureRecognizer:_chooseFilterTapGesture];
        
        _chooseFilterViews = nil;
        _chooseFilterTapGesture = nil;
        
        _isChooseFilterMode = NO;
        
        //  選択されたfilterを有効化
        [self setFilterWithFilter:tapFilter name:filterName size:CGSizeZero];
        
        //  タップしてないfilterの接続を解除
        for(GPUImageFilter *filter in _chooseFilterFilters)
        {
            if(_filter != filter)
            {
                [_stillCamera removeTarget:filter];
                [filter removeAllTargets];
            }
        }
        _chooseFilterFilters = nil;
        
        //  Shutterなどを表示する
        [UIView animateWithDuration:0.2 delay:0.0 options:0 animations:^{
            //
            for(UIView *view in _previewViews)
                view.alpha = 1.0;
            
            for(UIView *view in _shutterButtons)
                view.alpha = 1.0;
            
            for(UIView *view in _cameraRotateButtons)
                view.alpha = 1.0;
            
            for(UIView *view in _flashButons)
                view.alpha = 1.0;
            
            //
            //_chooseFilterBaseView.alpha = 0.0;
            
        } completion:^(BOOL finished) {
            //
            [_filter removeTarget:tapView];
            
            [_chooseFilterBaseView removeFromSuperview];
            _chooseFilterBaseView = nil;
        }];
        
        //  delegate
        if([_delegate respondsToSelector:@selector(cameraManager:didChangeFilter:)])
        {
            [_delegate cameraManager:self didChangeFilter:filterName];
        }
    }];
}

- (void)dissmissChooseEffect
{
    if(_isChooseFilterMode)
        [self handleFinishChooseFilterWithFilterName:_currentFilterName];
}

#pragma mark - shutter button image change

- (void)changeShutterButtonImageTo:(NSString*)imageName
{
    if(![_delegate respondsToSelector:@selector(cameraManager:shouldChangeShutterButtonImageTo:)] || [_delegate cameraManager:self shouldChangeShutterButtonImageTo:imageName])
    {
        UIImage *image = [UIImage imageNamed:imageName];
        for(UIButton *shutter in _shutterButtons)
        {
            [shutter setImage:image forState:UIControlStateNormal];
        }
    }
}

#pragma mark - cameraMode

//  カメラモードを切り替える
- (void)toggleCameraMode
{
    if(_cameraMode == CMCameraModeStill)
        self.cameraMode = CMCameraModeVideo;
    else
        self.cameraMode = CMCameraModeStill;
}

- (void)setCameraMode:(CMCameraMode)cameraMode
{
    //
    _cameraMode = cameraMode;
    
    //  ボタン変更
    [self changeShutterButtonImageTo:cameraMode==CMCameraModeStill?_stillShutterButtonImageName:_videoShutterButtonImageName];
    
    //  sessionpreset変更
    if(_stillCamera.inputCamera.position == AVCaptureDevicePositionFront)
    {
        //  フロントカメラの時
        if(_cameraMode == CMCameraModeStill)
        {
            if([_stillCamera.inputCamera supportsAVCaptureSessionPreset:_sessionPresetForFrontStill])
                _stillCamera.captureSessionPreset = _sessionPresetForFrontStill;
            else
                _stillCamera.captureSessionPreset = AVCaptureSessionPresetPhoto;
        }
        else
        {
            if([_stillCamera.inputCamera supportsAVCaptureSessionPreset:_sessionPresetForFrontVideo])
                _stillCamera.captureSessionPreset = _sessionPresetForFrontVideo;
            else
                _stillCamera.captureSessionPreset = AVCaptureSessionPresetHigh;
        }
    }
    else if(_cameraMode == CMCameraModeStill)
    {
        //  リアカメラの時
        if([_stillCamera.inputCamera supportsAVCaptureSessionPreset:_sessionPresetForStill])
            _stillCamera.captureSessionPreset = _sessionPresetForStill;
        else
            _stillCamera.captureSessionPreset = AVCaptureSessionPresetPhoto;
    }
    else
    {
        if([_stillCamera.inputCamera supportsAVCaptureSessionPreset:_sessionPresetForVideo])
            _stillCamera.captureSessionPreset = _sessionPresetForVideo;
        else
            _stillCamera.captureSessionPreset = AVCaptureSessionPresetHigh;
    }
}

@dynamic hasFlash;
- (BOOL)hasFlash
{
    return [_stillCamera.inputCamera hasTorch];
}

#pragma mark - notification

- (void)handleDeviceSubjectAreaDidChangeNotification:(NSNotification*)notification
{
    //NSLog(@"***handleDeviceSubjectAreaDidChangeNotification");
    [self setFocusModeContinousAutoFocus];
}

@end
