//
//  CameraManager.m
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "CameraManager.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <NSObject+EventDispatcher/NSObject+EventDispatcher.h>

#import "DeviceOrientation.h"
#import "UIImage+Normalize.h"
#import "NSDate+stringUtility.h"
#import "PreviewView.h"

//  KVOで追いかけるときに使うポインタ（メモリ番地をcontextとして使う）
static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * RecordingContext = &RecordingContext;
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;
static void * AdjustingFocusContext = &AdjustingFocusContext;
static void * DeviceOrientationContext = &DeviceOrientationContext;
static void * ReadyForTakePhotoContext = &ReadyForTakePhotoContext;

@interface CameraManager () <AVCaptureFileOutputRecordingDelegate>

//  Session
@property (strong, nonatomic) dispatch_queue_t sessionQueue;
@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;

//  Utilities
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (assign, nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (assign, nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (assign, nonatomic) BOOL lockInterfaceRotation;
@property (strong, nonatomic) id runtimeErrorHandlingObserver;

//
@property (assign, nonatomic) UIDeviceOrientation orientation;
@property (assign, nonatomic) BOOL isCameraRunning;
@property (assign, nonatomic) BOOL isCameraOpened;

//
@property (strong, nonatomic) NSTimer *recordingProgressTimer;
@property (strong, nonatomic) NSMutableArray *tmpMovieSavePathArray;    //ここに残ってるというのは、まだ処理に使ってるかもしれないという意味

@property (assign, nonatomic) BOOL focusViewShowHide;                   //  フォーカスの矩形の表示状態保持
@property (assign, nonatomic) BOOL adjustingFocus;                      //  タッチした時にフォーカス合わせ始めたことにしたい

@property (assign, nonatomic, readonly, getter = isReadyForTakePhoto) BOOL readyForTakePhoto;                 //  Shutterを切れる常態かどうか
@property (assign, nonatomic) NSInteger shutterReserveCount;            //  フォーカス中にShutter押された時用のフラグ

@property (assign, nonatomic) CGSize originalFocusCursorSize;
@property (assign, nonatomic) BOOL lastOpenState;

@end

#pragma mark -

@implementation CameraManager

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

- (void)setup
{
    //  初期化処理
    
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
    
    //  デフォルト動画撮影時間は10秒としておく
    _videoDuration = 10.0;
    
    //
    _tmpMovieSavePathArray = [NSMutableArray array];
    
    //  iPhoneがスリープするときやバックグラウンドにいくときにカメラをoffに
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    //  AVCaptureSessionを用意
	_session = [[AVCaptureSession alloc] init];
    
	//  使用許可の確認
	[self checkDeviceAuthorizationStatus];
	
    //  Session Queueの作成
	_sessionQueue = dispatch_queue_create("jp.dividual.CameraManager.session", DISPATCH_QUEUE_SERIAL);
    
	//  キューを使って処理
	dispatch_async(_sessionQueue, ^{
        //
        _backgroundRecordingID = UIBackgroundTaskInvalid;
		
		NSError *error = nil;
        
        //  カメラがフロントしかない、リアしか無いとか見極めて処理するため
        BOOL isFrontCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
        BOOL isRearCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
        
        //  探すデバイスを特定
        AVCaptureDevicePosition findPosition;
        if(isRearCameraAvailable)
            findPosition = AVCaptureDevicePositionBack;
        else if(isFrontCameraAvailable)
            findPosition = AVCaptureDevicePositionFront;
        
        findPosition = AVCaptureDevicePositionUnspecified;
        
        //  カメラデバイス探す
		AVCaptureDevice *videoDevice = [CameraManager deviceWithMediaType:AVMediaTypeVideo preferringPosition:findPosition];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
		
		if(error)
		{
			NSLog(@"%@", error);
		}
		
		if([_session canAddInput:videoDeviceInput])
		{
			[_session addInput:videoDeviceInput];
            
            //  保持
            _videoDeviceInput = videoDeviceInput;
		}
		
        //  動画用にオーディオデバイスも取得
		AVCaptureDevice *audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
		AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
		
		if(error)
		{
			NSLog(@"%@", error);
		}
		
		if([_session canAddInput:audioDeviceInput])
		{
			[_session addInput:audioDeviceInput];
		}
		
        //  動画書き出し用のインスタンス用意
		AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
		if([_session canAddOutput:movieFileOutput])
		{
			[_session addOutput:movieFileOutput];
            
			AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            
            //  動画の手ぶれ補正機能が使える時はとにかくONにしておく（iOS6以降）
			if([connection isVideoStabilizationSupported])
				[connection setEnablesVideoStabilizationWhenAvailable:YES];
            
            //  保持
            _movieFileOutput = movieFileOutput;
		}
		
        //  静止画撮影用のインスタンス用意
		AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
		if([_session canAddOutput:stillImageOutput])
		{
			[stillImageOutput setOutputSettings: @{AVVideoCodecKey : AVVideoCodecJPEG} ];
			[_session addOutput:stillImageOutput];
            
            //  保持
            _stillImageOutput = stillImageOutput;
		}
	});
}

//  カメラの使用開始処理
- (void)openCamera
{
    if(_isCameraOpened)
    {
        NSLog( @"カメラはすでにオープンされています" );
        return;
    }
    
    //  解像度設定の未設定チェック
    if( !_sessionPresetForStill )
        _sessionPresetForStill = AVCaptureSessionPresetPhoto;
    
    if( !_sessionPresetForVideo)
        _sessionPresetForVideo = AVCaptureSessionPresetHigh;
    
    if( !_sessionPresetForFrontStill )
        _sessionPresetForFrontStill = AVCaptureSessionPresetPhoto;
    
    if( !_sessionPresetForFrontVideo)
        _sessionPresetForFrontVideo = AVCaptureSessionPresetHigh;
    
    //  開始処理
    dispatch_async(_sessionQueue, ^{
        
        _isCameraOpened = YES;
        
        //  sessionRunningAndDeviceAuthorizedの変化をKVOで追いかける
		[self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningAndDeviceAuthorizedContext];
        
        //  stillImageOutput.capturingStillImageの変化をKVOで追いかける
		[self addObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:CapturingStillImageContext];
        
        //  movieFileOutput.recordingの変化をKVOで追いかける
		[self addObserver:self forKeyPath:@"movieFileOutput.recording" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:RecordingContext];
        
        //  フォーカス状態をKVOで追いかける
        [self addObserver:self forKeyPath:@"videoDeviceInput.device.adjustingFocus" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:AdjustingFocusContext];
        
        //  撮影可能になったかどうかを追いかける
        [self addObserver:self forKeyPath:@"readyForTakePhoto" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:ReadyForTakePhotoContext];
        
        //  Deviceの状態を常に監視してみる（ロックの時も）
        [[DeviceOrientation sharedManager] startAccelerometer];
        [[DeviceOrientation sharedManager] addObserver:self forKeyPath:@"orientation" options:NSKeyValueObservingOptionNew context:DeviceOrientationContext];
        
        //  画面が大きく変化したときのイベントを受けるように
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[_videoDeviceInput device]];
		
        //  エラーの受け取りをblockで指定
		__weak CameraManager *weakSelf = self;
		_runtimeErrorHandlingObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:_session queue:nil usingBlock:^(NSNotification *note) {
            //
			CameraManager *strongSelf = weakSelf;
			dispatch_async(strongSelf.sessionQueue, ^{
				//  リスタートかける
				[strongSelf.session startRunning];
                NSLog(@"**received AVCaptureSessionRuntimeErrorNotification");
			});
		}];
        
        //  カメラ処理開始
		[[self session] startRunning];
        
        //  ブーストをONにできればONに
        [self setLowLightBoost:YES];
        
        //  フォーカスを中心でcontinuesで
        [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:CGPointMake(0.5, 0.5) monitorSubjectAreaChange:NO];
    });
}


//  カメラの使用停止処理
- (void)closeCamera
{
    if(!_isCameraOpened)
    {
        NSLog( @"すでにカメラは閉じています" );
        return;
    }
    
    //  停止処理
    dispatch_async(_sessionQueue, ^{
        
        //  セッション停止
        [self.session stopRunning];
        
        //  登録したNotificationObserverを削除
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[_videoDeviceInput device]];
        [[NSNotificationCenter defaultCenter] removeObserver:_runtimeErrorHandlingObserver];
        _runtimeErrorHandlingObserver = nil;
        
        //  登録したObserverを削除
        [self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
        [self removeObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" context:CapturingStillImageContext];
        [self removeObserver:self forKeyPath:@"movieFileOutput.recording" context:RecordingContext];
        [self removeObserver:self forKeyPath:@"videoDeviceInput.device.adjustingFocus" context:AdjustingFocusContext];
        [[DeviceOrientation sharedManager] removeObserver:self forKeyPath:@"orientation" context:DeviceOrientationContext];
        [[DeviceOrientation sharedManager] stopAccelerometer];
        
        [self removeObserver:self forKeyPath:@"readyForTakePhoto" context:ReadyForTakePhotoContext];
        
        //
        _isCameraOpened = NO;
    });
}

#pragma mark - Notification

//  カメラからの映像が大きく変化した時のイベントをNotificationで受ける
- (void)subjectAreaDidChange:(NSNotification*)notification
{
    //  真ん中をcontinuesでフォーカス合わせるように（露出もcontinuesで）
    CGPoint devicePoint = CGPointMake(.5, .5);
    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

#pragma mark - kvo

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    //  contextで切り分ける
    
    if(context == CapturingStillImageContext)
    {
        //  静止画撮影中フラグの変化
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeIsCapturingStillImage" userInfo:@{@"state":@(isCapturingStillImage)}];
        });
    }
    else if(context == RecordingContext)
    {
        //  recordingStateの変化
        BOOL isRecording = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeIsRecordingVideo" userInfo:@{@"state":@(isRecording)}];
        });
    }
    else if(context == SessionRunningAndDeviceAuthorizedContext)
    {
        //  カメラ利用許可フラグの変化を追従（準備が完了したかどうかという意味合いで使える）
        BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isRunning)
            {
                //  開始イベント発行
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self dispatchEvent:@"open" userInfo:nil];
                });
            }
            else
            {
                //  終了イベント発行
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self dispatchEvent:@"close" userInfo:nil];
                });
            }
        });
    }
    else if(context == AdjustingFocusContext)
    {
        //  フォーカスの変化
        BOOL isAdjustingFocus = [change[NSKeyValueChangeNewKey] boolValue];
        
        //  カーソルを消すとか表示するとか
        if(isAdjustingFocus == NO)
        {
            [self dispatchEvent:@"hideFocusCursor" userInfo:nil];
            _focusViewShowHide = NO;
        }
        else if(_focusViewShowHide == NO)
        {
            //  フォーカス開始で、かつfocusViewが表示されてない場合（continuesで呼ばれた場合となる）
            CGPoint focusPos;
            if(_videoDeviceInput.device.focusPointOfInterestSupported)
                focusPos = _videoDeviceInput.device.focusPointOfInterest;
            else
                focusPos = CGPointMake(0.5, 0.5);
            
            [self showFocusCursorWithPos:focusPos isContinuous:YES];
        }
        
        //
        _adjustingFocus = isAdjustingFocus;
        
        //  Shutter予約がある場合は撮影する
        if(_shutterReserveCount && isAdjustingFocus == NO)
        {
            [self doTakePhoto];
        }
    }
    else if(context == DeviceOrientationContext)
    {
        //  デバイス回転の変化
        if([DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceDown || [DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceUp)
            return;
        
        if(_orientation != [DeviceOrientation sharedManager].orientation)
        {
            _orientation = [DeviceOrientation sharedManager].orientation;
            
            //
            [self dispatchEvent:@"didChangeDeviceOrientation" userInfo:@{ @"orientation":@(_orientation) }];//  UIDeviceOrientationを返してる
        }
    }
    else if(context == ReadyForTakePhotoContext)
    {
        BOOL isReadyTakePhoto = [change[NSKeyValueChangeNewKey] boolValue];
        
        NSLog(@"isReadyTakePhoto:%d", isReadyTakePhoto);
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - utility

//  フォーカスをあわせる処理を実行するメソッド
- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async([self sessionQueue], ^{
        //
        AVCaptureDevice *device = [_videoDeviceInput device];
        
        NSError *error = nil;
        if([device lockForConfiguration:&error])
        {
            //  フォーカスモードを設定
            if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode])
            {
                [device setFocusMode:focusMode];
                [device setFocusPointOfInterest:point];
            }
            
            //  露出モードを設定
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode])
            {
                [device setExposureMode:exposureMode];
                [device setExposurePointOfInterest:point];
            }
            
            //  画面変化を追従するかの設定
            [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];
            
            //  unlock
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@", error);
        }
    });
}

//  暗い時のブーストをかけるかどうか設定
- (void)setLowLightBoost:(BOOL)state
{
    dispatch_async([self sessionQueue], ^{
        //
        AVCaptureDevice *device = [[self videoDeviceInput] device];
        
        NSError *error = nil;
        if([device lockForConfiguration:&error])
        {
            if(device.isLowLightBoostSupported)
            {
                device.automaticallyEnablesLowLightBoostWhenAvailable = YES;
            }
            //  unlock
            [device unlockForConfiguration];
        }
    });
}

#pragma mark -

//  ユーザーがカメラ機能へのアクセスを許可するかどうか確認
- (void)checkDeviceAuthorizationStatus
{
    NSString *mediaType = AVMediaTypeVideo;
    
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        
        if(granted)
        {
            //  Granted access to mediaType
            self.deviceAuthorized = YES;
        }
        else
        {
            //  Not granted access to mediaType
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [[[UIAlertView alloc] initWithTitle:nil
                                            message:@"CameraManager doesn't have permission to use Camera, please change privacy settings"
                                           delegate:self
                                  cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
                
                self.deviceAuthorized = NO;
            });
        }
    }];
}

- (void)applicationDidEnterBackground:(NSNotification*)notification
{
    NSLog(@"applicationDidEnterBackground");
    
    //
    if(_isCameraOpened)
    {
        _lastOpenState = YES;
        [self closeCamera];
    }
    else
        _lastOpenState = NO;
}

- (void)applicationWillEnterForeground:(NSNotification*)notification
{
    NSLog(@"applicationWillEnterForeground");
    
    if(_lastOpenState)
    {
        [self openCamera];
    }
}

#pragma mark - ClassMethod

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = [devices firstObject];
    
    for(AVCaptureDevice *device in devices)
    {
        if([device position] == position)
        {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

#pragma mark -

- (BOOL)isSessionRunningAndDeviceAuthorized
{
    //  ここの変化を使ってopen/closeを呼ぶ（使用許可とセッション状態）
    return [[self session] isRunning] && [self isDeviceAuthorized];
}

+ (NSSet*)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
    return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (BOOL)isReadyForTakePhoto
{
    AVCaptureDevice *device =_videoDeviceInput.device;
    
    return !device.isAdjustingFocus && !device.isAdjustingExposure && !device.isAdjustingWhiteBalance && !_stillImageOutput.capturingStillImage;
}

+ (NSSet *)keyPathsForValuesAffectingReadyForTakePhoto
{
    return [NSSet setWithObjects:@"device.isAdjustingFocus", @"device.isAdjustingExposure", @"device.isAdjustingWhiteBalance", @"stillImageOutput.capturingStillImage", nil];
}

#pragma mark - focus関連

- (void)showFocusCursorWithPos:(CGPoint)pos isContinuous:(BOOL)isContinuous
{
    _focusViewShowHide = YES;
    
    //  とにかくイベントを送る
    [self dispatchEvent:@"showFocusCursor" userInfo:@{ @"position":[NSValue valueWithCGPoint:pos], @"isContinuous":@(isContinuous) }];
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

#pragma mark -

- (void)setFocusPoint:(CGPoint)pos
{
    //
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    //  タッチした位置へのフォーカスをサポートするかチェック
    if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus])
    {
        //  フォーカス合わせ始めたことにする
        _adjustingFocus = YES;
        
        [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:pos monitorSubjectAreaChange:YES];
        
        //  アニメーションスタート
        [self showFocusCursorWithPos:pos isContinuous:NO];
    }
}

- (void)setFlashMode:(CMFlashMode)flashMode
{
    _flashMode = flashMode;
    
    //  設定する
    dispatch_async([self sessionQueue], ^{
        //
        AVCaptureDevice *device = _videoDeviceInput.device;
        
        NSError *error = nil;
        if([device lockForConfiguration:&error])
        {
            switch(flashMode)
            {
                case CMFlashModeAuto:
                    device.flashMode = AVCaptureFlashModeAuto;
                    break;
                    
                case CMFlashModeOn:
                    device.flashMode = AVCaptureFlashModeOn;
                    break;
                    
                case CMFlashModeOff:
                    device.flashMode = AVCaptureFlashModeOff;
                    break;
            }
            
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"error:%@", error);
        }
    });
    
    //  イベント発行
    [self dispatchEvent:@"didChangeFlashMode" userInfo:@{ @"mode":@(flashMode) }];
}

#pragma mark - IBAction

- (void)changeFlashMode
{
    //  flashモードのボタンを押された（順に切り替える）
    self.flashMode = (_flashMode+1)%3;
}

//  撮影処理を内部的に呼ぶ場合はここ
- (void)doTakePhoto
{
    if(self.isReadyForTakePhoto)
        return;
    
    //  カウントデクリメント
    if(_shutterReserveCount)
        _shutterReserveCount--;
    
    //
    if(_cameraMode == CMCameraModeStill)
    {
        //  静止画撮影モード
        [self captureImage];
    }
    else
    {
        //  動画モード
        if(!_recordingProgressTimer)
            [self startVideoRec];//  動画撮影
        else
            [self stopVideoRec];//  録画中に押された場合は停止処理する
    }
}

//  シャッターボタンを押された
- (void)takePhoto
{
    //  フォーカスに対応してないとき用の処理
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if(!device.isFocusPointOfInterestSupported)
        _adjustingFocus = NO;
    
    //  ビデオモードの時は予約処理いらない
    if(_cameraMode == CMCameraModeVideo)
    {
        _shutterReserveCount = 0;
    }
    else
    {
        //  フォーカスを合わせてる途中だったら予約処理にする
        if(!self.isReadyForTakePhoto)
        {
            if(_shutterReserveCount<1)
                _shutterReserveCount++;
        }
    }
    
    if(_shutterReserveCount == 0)
        [self doTakePhoto];
}

//
- (void)rotateCameraPosition
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //  現在のカメラポジションを見て、解像度の切り替え考える
        if (_stillCamera.inputCamera.position == AVCaptureDevicePositionBack)
        {
            //  イベント発行
            dispatch_async(dispatch_get_main_queue(), ^{
                //  イベント発行
                [self dispatchEvent:@"willChangeCameraFrontBack" userInfo:@{ @"position":@(AVCaptureDevicePositionFront)} ];
            });
            
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
            //  イベント発行
            [self dispatchEvent:@"willChangeCameraFrontBack" userInfo:@{ @"position":@(AVCaptureDevicePositionBack)} ];
            
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
        
        //  フラッシュの有り無しに応じてGUIの表示/非表示
        //  フロントモードの時は左右入れ替えてプレビュー
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera] && _stillCamera)
        {
            //
            if(_stillCamera.cameraPosition == AVCaptureDevicePositionFront)
            {
                for(PreviewView *view in _previewViews)
                {
                    [view setInputRotation:kGPUImageFlipHorizonal atIndex:0];
                }
            }
            else
            {
                for(PreviewView *view in _previewViews)
                {
                    [view setInputRotation:kGPUImageNoRotation atIndex:0];
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            //  イベント発行
            [self dispatchEvent:@"didChangeCameraFrontBack" userInfo:@{ @"position":@(_stillCamera.inputCamera.position)} ];
        });
    });
}

#pragma mark - orientation utility

- (UIImageOrientation)currentImageOrientation
{
    BOOL isFront = _stillCamera.cameraPosition == AVCaptureDevicePositionFront?YES:NO;
    UIImageOrientation imageOrientation = UIImageOrientationLeft;
    switch (_orientation)
    {
        case UIDeviceOrientationPortrait:
            imageOrientation = UIImageOrientationRight;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            imageOrientation = UIImageOrientationLeft;
            break;
        case UIDeviceOrientationLandscapeLeft:
            imageOrientation = isFront?UIImageOrientationDown:UIImageOrientationUp;
            break;
        case UIDeviceOrientationLandscapeRight:
            imageOrientation = isFront?UIImageOrientationUp:UIImageOrientationDown;
            break;
        default:
            imageOrientation = UIImageOrientationUp;
            break;
    }
    
    return imageOrientation;
}

#pragma mark - capture

- (void)captureImage
{
    //  キャプチャー処理
    
    //  撮影後の処理をブロックで
    void (^completion)(UIImage *processedImage, UIImage *imageForAnimation, NSError *error) = ^(UIImage *originalImage, UIImage *imageForAnimation, NSError *error){
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                
                //  キャプチャー完了処理
                dispatch_async(dispatch_get_main_queue(), ^{
                    //
                    [self dispatchEvent:@"didPlayShutterSound" userInfo:@{ @"image":imageForAnimation }];
                    
                    //  フィルターを新しいのに切り替える（メモリ解放されるまでプレビューされない問題を回避するために）
                    if(!_silentShutterMode)
                    {
                        [_filter removeAllTargets];
                        [_stillCamera removeTarget:_filter];
                        
                        //  filterを作り替える
                        _filter = [self filterWithName:_currentFilterName];
                        [self prepareFilter];
                    }
                    
                    //
                    if(_silentShutterMode)
                    {
                        //  撮影中フラグをおろす
                        _isReadyForTakePhoto = YES;
                        
                        //  まだ撮影必要だったら撮影走らせる
                        if(_shutterReserveCount)
                        {
                            [self doTakePhoto];
                        }
                    }
                    else
                    {
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            //
                            GPUImageFilter *newFilter = (GPUImageFilter*)_filter;
                            while(newFilter.renderTarget == nil)
                            {
                                [NSThread sleepForTimeInterval:0.01];
                            }
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                
                                //  撮影中フラグをおろす
                                _isReadyForTakePhoto = YES;
                                
                                //  まだ撮影必要だったら撮影走らせる
                                if(_shutterReserveCount)
                                {
                                    [self doTakePhoto];
                                }
                            });
                        });
                    }
                });
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    
                    @autoreleasepool {
                        //  フィルターをここでかける
                        GPUImageFilter *filter = [self filterWithName:_currentFilterName];
                        GPUImagePicture *stillImageSource = [[GPUImagePicture alloc] initWithImage:originalImage];
                        [stillImageSource addTarget:filter];
                        [stillImageSource processImage];
                        
                        //
                        UIImage *filteredImage = [filter imageFromCurrentlyProcessedOutputWithOrientation:[self currentImageOrientation]];
                        
                        //  イベント発行（メインスレッドで実行）
                        dispatch_async(dispatch_get_main_queue(), ^{
                            
                            //  イベント発行
                            [self dispatchEvent:@"didCapturedImage" userInfo:@{ @"image":filteredImage} ];
                        });
                        
                        //
                        if(_autoSaveToCameraroll)
                        {
                            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                            
                            [library writeImageDataToSavedPhotosAlbum:UIImageJPEGRepresentation(filteredImage, _jpegQuality) metadata:nil completionBlock:^(NSURL *assetURL, NSError *error)
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
                    }
                });
            }
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
        //  アニメーション用の画像を作って用意しておく（フロントカメラのときは左右反転した画像にする）
        UIImage *imgForAnimation = nil;
        if(_stillCamera.inputCamera.position == AVCaptureDevicePositionFront)
            imgForAnimation = [_filter imageFromCurrentlyProcessedOutputWithOrientation:UIImageOrientationUpMirrored];
        else
            imgForAnimation = [_filter imageFromCurrentlyProcessedOutputWithOrientation:UIImageOrientationUp];
        
        
        //  念のためこれを呼ぶ
        [_filter prepareForImageCapture];
        
        //        //  通常の撮影
        //        [_stillCamera captureFixFlipPhotoAsImageProcessedUpToFilter:_filter orientation:_orientation withCompletionHandler:^(UIImage *processedImage, NSError *error) {
        //            //
        //            completion(processedImage, fixImage, error);
        //        }];
        
        //
        [_stillCamera captureDirectWithOrientation:_orientation completion:^(UIImage *image, NSError *error) {
            //
            completion(image, imgForAnimation, error);
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
    
    //  PreviewViewに表示してる元画像のサイズ
    return ((GPUImageFilter*)_filter).outputFrameSize;
}

- (void)setupTorch
{
    if([_stillCamera.inputCamera hasFlash])
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
            _stillCamera.inputCamera.torchMode = AVCaptureTorchModeAuto;
        }
        else if(_flashMode == CMFlashModeOn && [_stillCamera.inputCamera hasTorch])
        {
            //  ON
            _stillCamera.inputCamera.torchMode = AVCaptureTorchModeOn;
        }
        else
        {
            //  もともと消えてる想定でOFFの指定はしない
            _stillCamera.inputCamera.torchMode = AVCaptureTorchModeOn;
        }
        
        [_stillCamera.inputCamera unlockForConfiguration];
    }
}

- (void)offTorch
{
    if([_stillCamera.inputCamera hasFlash])
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
    //  event発行
    [self dispatchEvent:@"willStartVideoRecording" userInfo:nil];
    
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
        
        //  event発行
        [self dispatchEvent:@"didStartVideoRecording" userInfo:nil];
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
            //  イベント発行
            [self dispatchEvent:@"recordingVideo" userInfo:@{ @"time":@(self.recordedTime), @"remainTime":@(self.remainRecordTime)}];
        }
    }
}

- (void)saveVideoToCameraRoll
{
    if(_autoSaveToCameraroll && UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(_tmpMovieSavePath))
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UISaveVideoAtPathToSavedPhotosAlbum(_tmpMovieSavePath, self, @selector(video:didFinishSavingWithError:contextInfo:), nil);
        });
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
    
    //  照明必ず消す
    [self offTorch];
    
    //  カメラロールに保存してみる
    [self performSelector:@selector(saveVideoToCameraRoll) withObject:nil afterDelay:0.1];
    
    //  イベント発行
    [self dispatchEvent:@"didFinishedVideoRecording" userInfo:@{ @"movieURL":[NSURL fileURLWithPath:_tmpMovieSavePath] } ];
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


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"adjustingFocus"])
    {
        BOOL state = _stillCamera.inputCamera.isAdjustingFocus;
        
        //  カーソルを消すとか表示するとか
        if(state == NO)
        {
            [self dispatchEvent:@"hideFocusCursor" userInfo:nil];
            _focusViewShowHide = NO;
        }
        else if(_focusViewShowHide == NO)
        {
            //  フォーカス開始で、かつfocusViewが表示されてない場合
            CGPoint focusPos;
            if(_stillCamera.inputCamera.focusPointOfInterestSupported)
                focusPos = _stillCamera.inputCamera.focusPointOfInterest;
            else
                focusPos = CGPointMake(0.5, 0.5);
            
            [self showFocusCursorWithPos:focusPos isContinuous:YES];
        }
        
        //
        if(_shutterReserveCount && state == NO)
        {
            _adjustingFocus = NO;
            [self doTakePhoto];
        }
        else
        {
            _adjustingFocus = state;
        }
        
        // イベント発行
        [self dispatchEvent:@"adjustingFocus" userInfo:@{@"value":@(state)}];
        if( state == YES )
        {
            [self dispatchEvent:@"adjustFocusStart" userInfo:nil];
        }
        else
        {
            [self dispatchEvent:@"adjustFocusComplete" userInfo:nil];
        }
    }
    else if([keyPath isEqualToString:@"orientation"])
    {
        if([DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceDown || [DeviceOrientation sharedManager].orientation == UIDeviceOrientationFaceUp)
            return;
        
        if(_orientation != [DeviceOrientation sharedManager].orientation)
        {
            _orientation = [DeviceOrientation sharedManager].orientation;
            
            //
            [self dispatchEvent:@"didChangeDeviceOrientation" userInfo:@{ @"orientation":@(_orientation) }];//  UIDeviceOrientationを返してる
        }
    }
    else if( [keyPath isEqualToString:@"running"] )
    {
        // イベント発行
        if( _stillCamera.captureSession.running )
        {
            [self dispatchEvent:@"open" userInfo:nil];
        }
        else
        {
            [self dispatchEvent:@"close" userInfo:nil];
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
            filter = [[GPUImageFilter alloc] init];//[[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/default"];
        } break;
            
        case 1:{
            filter = [[GPUImageSepiaFilter alloc] init];
        } break;
            
        case 2: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/crossprocess"];
        } break;
            
        case 3: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/02"];
        } break;
            
        case 4: {
            filter = [[DLCGrayscaleContrastFilter alloc] init];
        } break;
            
        case 5: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/17"];
        } break;
            
        case 6: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/aqua"];
        } break;
            
        case 7: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/yellow-red"];
        } break;
            
        case 8: {
            filter = [[GPUImageToneCurveFilter alloc] initWithACV:@"CameraManager.bundle/Filters/06"];
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
    //  フィルターが存在するかチェック
    if(![_filterNameArray containsObject:name])
    {
        //  フィルター名がない
        NSLog(@"error:not exist filter %@", name);
        return;
    }
    
    //
    _currentFilterName = name;
    
    //  イベント発行
    NSInteger filterIdx = [_filterNameArray indexOfObject:name];
    [self dispatchEvent:@"willChangeFilter" userInfo:@{ @"name":name, @"index":@(filterIdx)} ];
    
    //  一旦接続を切る
    [self removeAllTargets];
    
    //
    _filter = [self filterWithName:_currentFilterName];
    
    //  フィルターを設定
    [self prepareFilter];
    
    //  イベント発行
    [self dispatchEvent:@"didChangeFilter" userInfo:@{ @"name":name, @"index":@(filterIdx)} ];
}

- (void)setFilterWithFilter:(GPUImageFilter*)filter name:(NSString*)name size:(CGSize)originalSize
{
    for(PreviewView *view in _previewViews)
        [_filter removeTarget:view];
    
    [_stillCamera removeTarget:_filter];
    
    _currentFilterName = name;
    _filter = filter;
    
    [_filter forceProcessingAtSize:originalSize];
    
    for(PreviewView *view in _previewViews)
    {
        [_filter addTarget:view];
        if(_stillCamera.cameraPosition == AVCaptureDevicePositionFront)
            [view setInputRotation:kGPUImageFlipHorizonal atIndex:0];
        else
            [view setInputRotation:kGPUImageNoRotation atIndex:0];
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

//  エフェクト一覧画面を表示するための画面を作る（指定するPreviewViewはprevieViewsとして追加済みでないとダメ）
- (void)showChooseEffectInPreviewView:(PreviewView*)previewView
{
    if(_isChooseFilterMode)
        return;
    
    if(![_previewViews containsObject:previewView])
    {
        NSLog(@"error:指定されたviewがpreviewViewsに入ってません。");
        return;
    }
    
    //
    //  イベントを送る
    [self dispatchEvent:@"showChangeFilterGUI" userInfo:nil];
    
    //
    _chooseFilterPreviewView = previewView;
    
    //  まずpreviewViewのGPUImageに
    //_chooseFilterPreviewView.previewMode = PreviewViewMode_GPUImage;
    
    //  表示するUIViewを作る
    UIView *baseView = [[UIView alloc] initWithFrame:previewView.frame];
    baseView.backgroundColor = [UIColor clearColor];
    
    //  9つのPreviewViewを作る（とりあえず配置してみる）
    CGFloat width = CGRectGetWidth(previewView.frame);
    CGFloat height = CGRectGetHeight(previewView.frame);
    
    CGFloat oneWidth = width/3.0;
    CGFloat oneHeight = height/3.0;
    
    int filterNum = MAX(_filterNameArray.count, 9); //9個最大
    
    NSMutableArray *filters = [NSMutableArray array];
    NSMutableArray *views = [NSMutableArray array];
    
    //
    CGSize originalSize = ((GPUImageFilter*)_filter).outputFrameSize;
    
    NSInteger curFilterIndex = [_filterNameArray indexOfObject:_currentFilterName];
    
    //
    for(int i=0;i<filterNum;i++)
    {
        int x = i%3;
        int y = i/3;
        
        //  フレーム指定
        //CGRect frame = CGRectMake(x*oneWidth, y*oneHeight, oneWidth, oneHeight);
        int xx = x-(curFilterIndex%3);
        int yy = y-(curFilterIndex/3);
        
        CGRect frame = CGRectMake(xx*width, yy*height, width, height);
        
        //  ライブフィルタープレビューのviewを作る
        PreviewView *view = [[PreviewView alloc] initWithFrame:frame];
        view.tag = 100+i;
        
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
    
    //
    [UIView animateWithDuration:0.4 delay:0.1 options:0 animations:^{
        //
        for(int i=0;i<filterNum;i++)
        {
            int x = i%3;
            int y = i/3;
            
            //  フレーム指定
            CGRect frame = CGRectMake(x*oneWidth, y*oneHeight, oneWidth, oneHeight);
            PreviewView *filterView = views[i];
            filterView.frame = frame;
        }
        
    } completion:^(BOOL finished) {
        //
        //  label表示
        for(UIView *view in _chooseFilterBaseView.subviews)
        {
            for(UILabel *label in view.subviews)
            {
                if([label isKindOfClass:[UILabel class]])
                {
                    label.frame = CGRectMake(0.0, CGRectGetHeight(label.superview.frame)-20.0, CGRectGetWidth(label.superview.frame), 20.0);
                }
            }
        }
        
        [UIView animateWithDuration:0.2 animations:^{
            for(UIView *view in _chooseFilterBaseView.subviews)
            {
                for(UILabel *label in view.subviews)
                {
                    if([label isKindOfClass:[UILabel class]])
                    {
                        label.alpha = 1.0;
                    }
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
    
    PreviewView *tapView = nil;
    
    for(PreviewView *view in _chooseFilterViews)
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
    
    PreviewView *tapView = _chooseFilterViews[index];
    GPUImageFilter *tapFilter = _chooseFilterFilters[index];
    
    //  選択されたviewを最前面に
    [_chooseFilterBaseView bringSubviewToFront:tapView];
    
    //  label消す
    [UIView animateWithDuration:0.2 animations:^{
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
    
    int filterNum = MAX(_filterNameArray.count, 9); //9個最大
    CGFloat width = _chooseFilterBaseView.bounds.size.width;
    CGFloat height = _chooseFilterBaseView.bounds.size.height;
    
    //  アニメーションさせる
    [UIView animateWithDuration:0.4 delay:0.1 options:0 animations:^{
        //  選ばれたviewを最大化
        //tapView.frame = _chooseFilterBaseView.frame;
        
        for(int i=0;i<filterNum;i++)
        {
            int x = i%3;
            int y = i/3;
            
            int xx = x-(index%3);
            int yy = y-(index/3);
            
            CGRect frame = CGRectMake(xx*width, yy*height, width, height);
            
            PreviewView *filterView = _chooseFilterViews[i];
            filterView.frame = frame;
        }
        
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
        
        //
        [_filter removeTarget:tapView];
        [_chooseFilterBaseView removeFromSuperview];
        _chooseFilterBaseView = nil;
        
        //  イベント発行
        [self dispatchEvent:@"dismissChangeFilterGUI" userInfo:@{ @"name":filterName , @"index":@(index) }];
    }];
    
}

- (void)dissmissChooseEffect
{
    if(_isChooseFilterMode)
        [self handleFinishChooseFilterWithFilterName:_currentFilterName];
}

@dynamic currentFilterIndex;
- (NSInteger)currentFilterIndex
{
    return [_filterNameArray indexOfObject:_currentFilterName];
}

#pragma mark - cameraMode

//  カメラモードを切り替える
- (void)toggleCameraMode
{
    if(_cameraMode == CMCameraModeStill)
    {
        self.cameraMode = CMCameraModeVideo;
        [self offTorch];
    }
    else
    {
        self.cameraMode = CMCameraModeStill;
        self.flashMode = _flashMode;
    }
}

- (void)setCameraMode:(CMCameraMode)cameraMode
{
    //
    _cameraMode = cameraMode;
    
    //  イベント発行
    [self dispatchEvent:@"willChangeCameraMode" userInfo:@{ @"mode":@(_cameraMode)} ];
    
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
    
    //  イベント発行
    [self dispatchEvent:@"didChangeCameraMode" userInfo:@{ @"mode":@(_cameraMode)} ];
    
}

@dynamic hasFlash;
- (BOOL)hasFlash
{
    return [_stillCamera.inputCamera hasFlash];
}

#pragma mark - notification

- (void)handleDeviceSubjectAreaDidChangeNotification:(NSNotification*)notification
{
    //NSLog(@"***handleDeviceSubjectAreaDidChangeNotification");
    [self setFocusModeContinousAutoFocus];
}

#pragma mark - zoom

//  ズーム値設定
- (void)setZoomScale:(CGFloat)zoomScale
{
    if(_stillCamera && [_stillCamera.inputCamera respondsToSelector:@selector(activeFormat)])
    {
        NSError *error = nil;
        if([_stillCamera.inputCamera lockForConfiguration:&error])    //  devicelock
        {
            CGFloat max = self.maxZoomScale;
            zoomScale = zoomScale>max?max:zoomScale<1.0?1.0:zoomScale;
            _stillCamera.inputCamera.videoZoomFactor = zoomScale;
            
            [_stillCamera.inputCamera unlockForConfiguration];
        }
    }
}

- (CGFloat)zoomScale
{
    if(_stillCamera && [_stillCamera.inputCamera respondsToSelector:@selector(activeFormat)])
    {
        return _stillCamera.inputCamera.videoZoomFactor;
    }
    
    return 1.0;
}

//  ズームの最大スケール
- (CGFloat)maxZoomScale
{
    if(_stillCamera && [_stillCamera.inputCamera respondsToSelector:@selector(activeFormat)])
    {
        return _stillCamera.inputCamera.activeFormat.videoMaxZoomFactor;
    }
    
    return 1.0;
}

@end
