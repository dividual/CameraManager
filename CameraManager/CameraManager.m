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

@interface CameraManager () <AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

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
@property (strong, nonatomic) NSString *tmpMovieSavePath;
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
        
//        //  サイレントモード用のdataOutput作成
//        AVCaptureVideoDataOutput*   dataOutput;
//        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey, nil];
//
//        
//        dataOutput = [[AVCaptureVideoDataOutput alloc] init];
//        [dataOutput autorelease];
//        dataOutput.videoSettings = settings;
//        [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
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
		[_session startRunning];
        
        //  ブーストをONにできればONに
        [self setLowLightBoost:YES];
        
        //  フォーカスを中心でcontinuesで
        [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:CGPointMake(0.5, 0.5) monitorSubjectAreaChange:NO];
        
        //  カメラモードを指定
        [self setCameraMode:CMCameraModeStill];
        
        //  フラッシュモード指定しておく
        [self setDeviceFlashMode:_flashMode];
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
        
        if(isReadyTakePhoto)
        {
            //  Shutter予約がある場合は撮影する
            if(_shutterReserveCount)
            {
                [self doTakePhoto];
            }
        }
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
                NSLog(@"lowLightBoost:%d", state);
                device.automaticallyEnablesLowLightBoostWhenAvailable = state;
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
    return [_session isRunning] && [self isDeviceAuthorized];
}

+ (NSSet*)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
    return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (BOOL)isReadyForTakePhoto
{
    AVCaptureDevice *device =_videoDeviceInput.device;
    
    if(_cameraMode == CMCameraModeStill)
        return !device.isAdjustingFocus && !_stillImageOutput.capturingStillImage;
    else
        return !device.isAdjustingFocus && !_movieFileOutput.recording;
}

+ (NSSet *)keyPathsForValuesAffectingReadyForTakePhoto
{
    return [NSSet setWithObjects:@"videoDeviceInput.device.adjustingFocus", @"stillImageOutput.capturingStillImage", nil];
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
    
    //  デバイス側にも指定
    [self setDeviceFlashMode:_flashMode];
        
    //  イベント発行
    [self dispatchEvent:@"didChangeFlashMode" userInfo:@{ @"mode":@(_flashMode) }];
}

- (void)setDeviceFlashMode:(CMFlashMode)flashMode
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if([device hasFlash])
    {
        //  設定する
        dispatch_async([self sessionQueue], ^{
            //
            
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
    }
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
    //  静止画の時だけ状態によりブロック
    if(!self.isReadyForTakePhoto && _cameraMode == CMCameraModeStill)
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
    //  回転させるときに一旦focusの表示消すように送る
    if(_focusViewShowHide)
    {
        [self dispatchEvent:@"hideFocusCursor" userInfo:nil];
        _focusViewShowHide = NO;
    }
    
    //
    dispatch_async([self sessionQueue], ^{
        //
		AVCaptureDevice *currentVideoDevice = [_videoDeviceInput device];
        
        //
		AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
		AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
		
		switch(currentPosition)
		{
			case AVCaptureDevicePositionUnspecified:
				preferredPosition = AVCaptureDevicePositionBack;
				break;
                
			case AVCaptureDevicePositionBack:
				preferredPosition = AVCaptureDevicePositionFront;
				break;
                
			case AVCaptureDevicePositionFront:
				preferredPosition = AVCaptureDevicePositionBack;
				break;
		}
        
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            //  イベント発行
            [self dispatchEvent:@"willChangeCameraFrontBack" userInfo:@{ @"position":@(preferredPosition)} ];
        });
        
        //  指定デバイスを探す
		AVCaptureDevice *videoDevice = [CameraManager deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
		
        //
		[_session beginConfiguration];
		
        //  sessionから今のデバイスを外す
		[_session removeInput:[self videoDeviceInput]];
        
        //  sessionに追加するまえにpresetを変更
        NSString *lastPreset = _session.sessionPreset;
        if(preferredPosition == AVCaptureDevicePositionBack)
        {
            if(_cameraMode == CMCameraModeStill)
                _session.sessionPreset = _sessionPresetForStill;
            else
                _session.sessionPreset = _sessionPresetForVideo;
        }
        else
        {
            if(_cameraMode == CMCameraModeStill)
                _session.sessionPreset = _sessionPresetForFrontStill;
            else
                _session.sessionPreset = _sessionPresetForFrontVideo;
        }
        
        //  追加できるか調べて追加
		if ([_session canAddInput:videoDeviceInput])
		{
            //  変更できれば変更
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
			
			[_session addInput:videoDeviceInput];
			_videoDeviceInput = videoDeviceInput;
		}
		else
		{
            //  sessionに追加するまえにpresetを変更
            _session.sessionPreset = lastPreset;
            
            //  ダメな場合戻す
			[_session addInput:_videoDeviceInput];
		}
		
        //
		[_session commitConfiguration];
		
        //  イベント発行
		dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeCameraFrontBack" userInfo:@{ @"position":@(_videoDeviceInput.device.position)}];
		});
	});
}

#pragma mark - orientation utility

- (UIImageOrientation)currentImageOrientation
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    BOOL isFront = device.position == AVCaptureDevicePositionFront?YES:NO;
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

- (AVCaptureVideoOrientation)currentVideoOrientation
{    
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationPortrait;
    switch (_orientation)
    {
        case UIDeviceOrientationPortrait:
            videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIDeviceOrientationLandscapeLeft:
            videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIDeviceOrientationLandscapeRight:
            videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        default:
            videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
    }
    
    return videoOrientation;
}


#pragma mark - capture

- (void)captureImage
{
    //  キャプチャー処理
    if(_silentShutterMode)
    {
        //  サイレントモードの時は別処理
//        [self captureImageSilentWithCompletion:^(UIImage *processedImage, UIImage *imageForAnimation, NSError *error) {
//            
//            [self capturedImage:processedImage animationImage:imageForAnimation error:error];
//        }];
    }
    else
    {
        //  アニメーション用の画像を作って用意しておく（フロントカメラのときは左右反転した画像にする）
        UIImage *imageForAnimation = nil;
        
        [self captureStillWithCompletion:^(UIImage *image, NSError *error) {
            //
            [self capturedImage:image animationImage:imageForAnimation error:error];
        }];
    }
}

- (void)captureStillWithCompletion:(void(^)(UIImage *image, NSError *error))completion
{
    dispatch_async(_sessionQueue, ^{
        
		//  orientationを設定
		[[_stillImageOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[self currentVideoOrientation]];
				
		//  撮影処理
		[_stillImageOutput captureStillImageAsynchronouslyFromConnection:[_stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
			
			if (imageDataSampleBuffer)
			{
				NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
				UIImage *image = [[UIImage alloc] initWithData:imageData];
                
                completion(image, nil);
			}
		}];
	});
}

- (void)capturedImage:(UIImage*)originalImage animationImage:(UIImage*)animationImage error:(NSError*)error
{
    //  イベント発行
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dispatchEvent:@"didCapturedImage" userInfo:@{ @"image":originalImage }];
    });
    
    //
    if(_autoSaveToCameraroll)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            @autoreleasepool {
                ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                
                [library writeImageDataToSavedPhotosAlbum:UIImageJPEGRepresentation(originalImage, _jpegQuality) metadata:nil completionBlock:^(NSURL *assetURL, NSError *error)
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
        
    }
}

#pragma mark - video

- (void)setupTorch
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if([device hasFlash])
    {
        //  フラッシュの設定
        NSError *error = nil;
        if (![device lockForConfiguration:&error])
        {
            NSLog(@"Error locking for configuration: %@", error);
        }
        
        //  フラッシュの準備（上記のロックをかけてからでないと処理できないっぽい）
        if(_flashMode == CMFlashModeAuto && [device hasTorch])
        {
            //  自動
            device.torchMode = AVCaptureTorchModeAuto;
        }
        else if(_flashMode == CMFlashModeOn && [device hasTorch])
        {
            //  ON
            device.torchMode = AVCaptureTorchModeOn;
        }
        else if([device hasTorch])
        {
            //  OFF
            device.torchMode = AVCaptureTorchModeOff;
        }
        
        [device unlockForConfiguration];
    }
}

- (void)offTorch
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if([device hasFlash])
    {
        [device lockForConfiguration:nil];
        [device setTorchMode:AVCaptureTorchModeOff];
        [device unlockForConfiguration];
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
    
    //
    dispatch_async([self sessionQueue], ^{
        
		if(!_movieFileOutput.isRecording)
		{
            //  録画開始
			_lockInterfaceRotation = YES;
			
			if ([[UIDevice currentDevice] isMultitaskingSupported])
			{
				[self setBackgroundRecordingID:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil]];
			}
			
			// Update the orientation on the movie file output video connection before starting recording.
			[[_movieFileOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[self currentVideoOrientation]];
			
			//  照明つけるとか
            [self setupTorch];
            
			//  Start recording to a temporary file.
			_tmpMovieSavePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[self makeTempMovieFileName]];
            
            unlink([_tmpMovieSavePath UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
            
            //  arrayに追加しておく
            [_tmpMovieSavePathArray addObject:_tmpMovieSavePath];
            
//            //  最大録画秒数指定（これで止まるとなんかいろいろうまく行かないので、タイマーで止める）
//            _movieFileOutput.maxRecordedDuration = CMTimeMakeWithSeconds( _videoDuration, NSEC_PER_SEC );
            
            //  録画スタート
			[_movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:_tmpMovieSavePath] recordingDelegate:self];
            
            //  タイマースタート
            dispatch_async(dispatch_get_main_queue(), ^{
                //
                [self startRecordingProgressTimer];
                
                //event発行
                [self dispatchEvent:@"didStartVideoRecording" userInfo:nil];
            });
        }
	});
}

- (void)stopVideoRec
{
    dispatch_async([self sessionQueue], ^{
        
        [_movieFileOutput stopRecording];
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
    CMTime time = _movieFileOutput.recordedDuration;
    
    return CMTimeGetSeconds(time);
}

- (NSTimeInterval)remainRecordTime
{
    return _videoDuration - self.recordedTime;
}

#pragma mark - AVCaptureDeviceFileOutputDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    BOOL recordedSuccessfully = YES;
    if ([error code] != noErr)
    {
        id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value)
        {
            recordedSuccessfully = [value boolValue];
        }
    }
    
	_lockInterfaceRotation = NO;
	
    //
	UIBackgroundTaskIdentifier backgroundRecordingID = _backgroundRecordingID;
    _backgroundRecordingID = UIBackgroundTaskInvalid;

    //  プログレスのタイマー止める
    [self stopRecordingProgressTimer];
    
    //  照明必ず消す
    [self offTorch];
    
    //
    if(recordedSuccessfully == NO)
    {
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didFinishedVideoRecording" userInfo:nil ];
        });
    }
    else
    {
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didFinishedVideoRecording" userInfo:@{ @"movieURL":outputFileURL } ];
        });
        
        //  保存処理
        if(_autoSaveToCameraroll)
        {
            [[[ALAssetsLibrary alloc] init] writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
                
                if (error)
                    NSLog(@"%@", error);
                
                NSLog(@"saveVideo to CameraRoll Finished:%@", outputFileURL);
                
                if([_tmpMovieSavePathArray containsObject:outputFileURL.path])
                {
                    //  まだ消してはいけない
                    //  リストからは消しておく
                    [_tmpMovieSavePathArray removeObject:outputFileURL.path];
                }
                else
                {
                    //  もう処理が終わってるらしいので消す
                    [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
                    
                    NSLog(@"removeFile:%@", outputFileURL.path);
                }
                
                //
                if (backgroundRecordingID != UIBackgroundTaskInvalid)
                    [[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
            }];
        }
    }
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
    
    dispatch_async(_sessionQueue, ^{
        
        //  sessionpreset変更
        AVCaptureDevice *device = _videoDeviceInput.device;
        if(device.position == AVCaptureDevicePositionFront)
        {
            //  フロントカメラの時
            if(_cameraMode == CMCameraModeStill)
            {
                if([device supportsAVCaptureSessionPreset:_sessionPresetForFrontStill])
                    _session.sessionPreset = _sessionPresetForFrontStill;
                else
                    _session.sessionPreset = AVCaptureSessionPresetPhoto;
            }
            else
            {
                if([device supportsAVCaptureSessionPreset:_sessionPresetForFrontVideo])
                    _session.sessionPreset = _sessionPresetForFrontVideo;
                else
                    _session.sessionPreset = AVCaptureSessionPresetHigh;
            }
        }
        else if(_cameraMode == CMCameraModeStill)
        {
            //  リアカメラの時
            if([device supportsAVCaptureSessionPreset:_sessionPresetForStill])
                _session.sessionPreset = _sessionPresetForStill;
            else
                _session.sessionPreset = AVCaptureSessionPresetPhoto;
        }
        else
        {
            if([device supportsAVCaptureSessionPreset:_sessionPresetForVideo])
                _session.sessionPreset = _sessionPresetForVideo;
            else
                _session.sessionPreset = AVCaptureSessionPresetHigh;
        }
        
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeCameraMode" userInfo:@{ @"mode":@(_cameraMode)} ];
        });
    });
    
}

@dynamic hasFlash;
- (BOOL)hasFlash
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    return [device hasFlash];
}

#pragma mark - zoom

//  ズーム値設定
- (void)setZoomScale:(CGFloat)zoomScale
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if(device && [device respondsToSelector:@selector(activeFormat)])
    {
        NSError *error = nil;
        if([device lockForConfiguration:&error])    //  devicelock
        {
            CGFloat max = self.maxZoomScale;
            zoomScale = zoomScale>max?max:zoomScale<1.0?1.0:zoomScale;
            device.videoZoomFactor = zoomScale;
            
            [device unlockForConfiguration];
        }
    }
}

- (CGFloat)zoomScale
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if(device && [device respondsToSelector:@selector(activeFormat)])
    {
        return device.videoZoomFactor;
    }
    
    return 1.0;
}

//  ズームの最大スケール
- (CGFloat)maxZoomScale
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if(device && [device respondsToSelector:@selector(activeFormat)])
    {
        return device.activeFormat.videoMaxZoomFactor;
    }
    
    return 1.0;
}

@end
