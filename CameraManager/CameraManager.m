//
//  CameraManager.m
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//


#import "CameraManager.h"

#import <mach/mach.h>

#import <AssetsLibrary/AssetsLibrary.h>
#import <NSObject+EventDispatcher/NSObject+EventDispatcher.h>
#import <KVOController/FBKVOController.h>

#import "UIImage+Normalize.h"
#import "NSDate+stringUtility.h"
#import "PreviewView.h"
#import "SaveToCameraRollOperation.h"
#import <MotionOrientation@PTEz/MotionOrientation.h>
#import <NNProfiler/NNProfiler.h>

//  KVOで追いかけるときに使うポインタ（メモリ番地をcontextとして使う）
static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * RecordingContext = &RecordingContext;
static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;
static void * AdjustingFocusContext = &AdjustingFocusContext;
static void * DeviceOrientationContext = &DeviceOrientationContext;

@interface CameraManager () <AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

//  Session
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic) dispatch_queue_t captureCurrentFrameQueue;
@property (strong, nonatomic) AVCaptureVideoDataOutput *videoDataOutput;

@property (nonatomic) dispatch_queue_t saveQueue;

//  Utilities
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (assign, nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (assign, nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (assign, nonatomic) BOOL lockInterfaceRotation;
@property (strong, nonatomic) id runtimeErrorHandlingObserver;

@property (assign, nonatomic) BOOL isCameraRunning;
@property (assign, nonatomic) BOOL isCameraOpened;

//
@property (strong, nonatomic) NSTimer *recordingProgressTimer;
@property (strong, nonatomic) NSString *tmpMovieSavePath;
@property (strong, nonatomic) NSMutableArray *tmpMovieSavePathArray;    //  ここに残ってるというのは、まだ処理に使ってるかもしれないという意味

@property (assign, nonatomic) BOOL focusViewShowHide;                   //  フォーカスの矩形の表示状態保持
@property (assign, nonatomic) BOOL adjustingFocus;                      //  タッチした時にフォーカス合わせ始めたことにしたい

@property (assign, nonatomic, readonly, getter = isReadyForTakePhoto) BOOL readyForTakePhoto;                 //  Shutterを切れる常態かどうか
@property (assign, nonatomic) NSInteger shutterReserveCount;            //  フォーカス中にShutter押された時用のフラグ

@property (assign, nonatomic) CGSize originalFocusCursorSize;
@property (assign, nonatomic) BOOL lastOpenState;

//  captureの処理用
@property (copy, nonatomic) void (^captureCompletion)(UIImage *capturedImage);
@property (assign, nonatomic) BOOL isImageForAnimation;

@end

#pragma mark -

@implementation CameraManager{
	NSOperationQueue* _saveToCameraRoll_queue;
	BOOL _autoFocusEnabled;
	FBKVOController* _kvoController;
	UIDeviceOrientation _orientation;
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

#pragma mark - memory utility

//  空きメモリ量を取得（MB）
+ (float)getFreeMemory{
    mach_port_t hostPort;
    mach_msg_type_number_t hostSize;
    vm_size_t pagesize;
    
    hostPort = mach_host_self();
    hostSize = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    host_page_size(hostPort, &pagesize);
    vm_statistics_data_t vmStat;
    
    if (host_statistics(hostPort, HOST_VM_INFO, (host_info_t)&vmStat, &hostSize) != KERN_SUCCESS)
    {
        NSLog(@"[SystemMonitor] Failed to fetch vm statistics");
        return 0.0;
    }
    
    natural_t freeMemory = vmStat.free_count * pagesize;
    
//    return (float)freeMemory/1024.0/1024.0;
//	NSLog( @"free memory = %fMB", (float)freeMemory/1024.0/1024.0 );
	return (float)1024.0;
}


#pragma mark -

/// 初期化時に1度だけ呼ばれます
- (void)setup{
	_kvoController = [[FBKVOController alloc] initWithObserver:self];
	_autoFocusEnabled = YES;//  初期化処理
    _flashMode = CMFlashModeOff;//  デフォルトのフラッシュモード指定しておく
    _delayTimeForFlash = 0.25;//  デフォルトのdelaytime
//    _autoSaveToCameraroll = YES;//  デフォルトはカメラロール保存自動
    _silentShutterMode = NO;//  デフォルトはサイレントモードはOFF
    _jpegQuality = 0.9;//  デフォルトのJpegQuality
    _videoDuration = 10.0;//  デフォルト動画撮影時間は10秒としておく
    _tmpMovieSavePathArray = [NSMutableArray array];
    
    //  iPhoneがスリープするときやバックグラウンドにいくときにカメラをoffに
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
	// 画面の回転を監視
	[MotionOrientation initialize];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(motionOrientationChanged:) name:MotionOrientationChangedNotification object:nil];
	
    
	_session = [[AVCaptureSession alloc] init];//  AVCaptureSessionを用意
	[self checkDeviceAuthorizationStatus];//  使用許可の確認
	_sessionQueue = dispatch_queue_create("jp.dividual.CameraManager.session", DISPATCH_QUEUE_SERIAL);//  Session Queueの作成
    _captureCurrentFrameQueue = dispatch_queue_create("jp.dividual.CameraManager.captureCurrentFrame", DISPATCH_QUEUE_SERIAL);
    _saveQueue = dispatch_queue_create("jp.dividual.CameraManager.saveQueue", DISPATCH_QUEUE_SERIAL);//  保存用キュー
	
	_saveToCameraRoll_queue = [[NSOperationQueue alloc] init];
	_saveToCameraRoll_queue.maxConcurrentOperationCount = 5;// これを超えるとiPodTouchで保存失敗が発生する可能性があります。
    
	//  キューを使って処理
	dispatch_async(_sessionQueue, ^{
        _backgroundRecordingID = UIBackgroundTaskInvalid;
		
		NSError *error = nil;
        
        //  カメラがフロントしかない、リアしか無いとか見極めて処理するため
        BOOL isFrontCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
        BOOL isRearCameraAvailable = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
        
        //  探すデバイスを特定
        AVCaptureDevicePosition findPosition = AVCaptureDevicePositionUnspecified;
        if(isRearCameraAvailable)
            findPosition = AVCaptureDevicePositionBack;
        else if(isFrontCameraAvailable)
            findPosition = AVCaptureDevicePositionFront;
        
        //  カメラデバイス探す
		AVCaptureDevice *videoDevice = [CameraManager deviceWithMediaType:AVMediaTypeVideo preferringPosition:findPosition];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
		
		// 暗い場所でのISOブーストをオン
		if( videoDevice.lowLightBoostSupported ){
			[videoDevice lockForConfiguration:&error];
			videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = YES;
			[videoDevice unlockForConfiguration];
		}
		
		if(error){
			NSLog(@"%@", error);
		}
		
		if([_session canAddInput:videoDeviceInput]){
			[_session addInput:videoDeviceInput];
            _videoDeviceInput = videoDeviceInput;//  保持
		}
		
		
        //  動画書き出し用のインスタンス用意
		AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
		if([_session canAddOutput:movieFileOutput]){
            //  動画モードの時だけ追加して使う
			//[_session addOutput:movieFileOutput];
			AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            
            //  動画の手ぶれ補正機能が使える時はとにかくONにしておく（iOS6以降）
			if([connection isVideoStabilizationSupported]){
				[connection setEnablesVideoStabilizationWhenAvailable:YES];
			}
            _movieFileOutput = movieFileOutput;//  保持
		}
		
        //  静止画撮影用のインスタンス用意
		AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
		if([_session canAddOutput:stillImageOutput]){
			[stillImageOutput setOutputSettings: @{AVVideoCodecKey : AVVideoCodecJPEG} ];
			[_session addOutput:stillImageOutput];
            _stillImageOutput = stillImageOutput;//  保持
		}
        
        //  サイレントモード用のdataOutput作成
        AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
        dataOutput.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA) };
        [dataOutput setSampleBufferDelegate:self queue:_captureCurrentFrameQueue];
        dataOutput.alwaysDiscardsLateVideoFrames = YES;
        if([_session canAddOutput:dataOutput]){
            [_session addOutput:dataOutput];
            _videoDataOutput = dataOutput;//  保持
        }
		
		/// 各種イベント監視
		// フォーカス
		[_kvoController observe:videoDevice keyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew block:^(id observer, id object, NSDictionary *change) {
			NSNumber* value = change[@"new"];
			if( value.boolValue == YES ){
				// フォーカス開始
			} else {
				// フォーカス完了
				// ビデオ撮影中なら、タップしてフォーカス後にオートフォーカスをオフにする
				if( _movieFileOutput.isRecording ){
					[self disableAutoFocus];
				}
			}
		}];
	});
}


/// デバイスの姿勢が変更された時に呼ばれます
- (void)motionOrientationChanged:(NSNotification *)notification{
	UIDeviceOrientation orientation = [MotionOrientation sharedInstance].deviceOrientation;
	// 上向きと下向きは無視
	if( orientation == UIDeviceOrientationFaceUp || orientation == UIDeviceOrientationFaceDown ){
		return;
	}
	
	_orientation = orientation;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self dispatchEvent:@"didChangeDeviceOrientation" userInfo:@{ @"orientation":@(_orientation) }];//  UIDeviceOrientationを返してる
	});
}



///  カメラの使用開始処理
- (void)openCamera{
    if(_isCameraOpened){
        NSLog( @"カメラはすでにオープンされています" );
		UIAlertView* alertView = [[UIAlertView alloc] init];
		alertView.message = @"すでにカメラは起動しています";
		[alertView addButtonWithTitle:@"OK"];
		[alertView show];
        return;
    }
	
	 _isCameraOpened = YES;
    
    //  解像度設定の未設定チェック
    if(!_sessionPresetForStill )
        _sessionPresetForStill = AVCaptureSessionPresetPhoto;
    
    if(!_sessionPresetForVideo)
        _sessionPresetForVideo = AVCaptureSessionPresetHigh;
    
    if(!_sessionPresetForFrontStill )
        _sessionPresetForFrontStill = AVCaptureSessionPresetPhoto;
    
    if(!_sessionPresetForFrontVideo)
        _sessionPresetForFrontVideo = AVCaptureSessionPresetHigh;
    
    if(!_sessionPresetForSilentStill)
        _sessionPresetForSilentStill = AVCaptureSessionPresetiFrame1280x720;
    
    if(!_sessionPresetForSilentFrontStill)
        _sessionPresetForSilentFrontStill = AVCaptureSessionPresetiFrame1280x720;
    
	
	
//	[self setCameraMode:_cameraMode];//  カメラモードを指定

		
    //  開始処理
    dispatch_async(_sessionQueue, ^{
        //  sessionRunningAndDeviceAuthorizedの変化をKVOで追いかける
		[self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningAndDeviceAuthorizedContext];
        
        //  stillImageOutput.capturingStillImageの変化をKVOで追いかける
		[self addObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:CapturingStillImageContext];
        
        //  movieFileOutput.recordingの変化をKVOで追いかける
		[self addObserver:self forKeyPath:@"movieFileOutput.recording" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:RecordingContext];
        
        //  フォーカス状態をKVOで追いかける
        [self addObserver:self forKeyPath:@"videoDeviceInput.device.adjustingFocus" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:AdjustingFocusContext];
        
        //  画面が大きく変化したときのイベントを受けるように
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[_videoDeviceInput device]];
		
        //  エラーの受け取りをblockで指定
		__weak CameraManager *weakSelf = self;
		_runtimeErrorHandlingObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:_session queue:nil usingBlock:^(NSNotification *note) {
			CameraManager *strongSelf = weakSelf;
			dispatch_async(strongSelf.sessionQueue, ^{
				//  リスタートかける
				[strongSelf.session startRunning];
                NSLog(@"**received AVCaptureSessionRuntimeErrorNotification");
			});
		}];
        
		_session.sessionPreset = AVCaptureSessionPresetPhoto;
		
        //  iPhone5sの手ブレをONにしてみる
		if(_stillImageOutput.stillImageStabilizationSupported){
			_stillImageOutput.automaticallyEnablesStillImageStabilizationWhenAvailable = YES;
		}
		
		//  カメラ処理開始
		[_session startRunning];
		
		[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:CGPointMake(0.5, 0.5) monitorSubjectAreaChange:NO];//  フォーカスを中心でcontinuesで
		[self setDeviceFlashMode:_flashMode];//  フラッシュモード指定しておく
    });
}


//  カメラの使用停止処理
- (void)closeCamera{
    if(!_isCameraOpened){
        NSLog( @"すでにカメラは閉じています" );
        return;
    }
    
    //  停止処理
    dispatch_async(_sessionQueue, ^{
        [self.session stopRunning];//  セッション停止
        dispatch_async(dispatch_get_main_queue(), ^{
            //  登録したNotificationObserverを削除
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[_videoDeviceInput device]];
            [[NSNotificationCenter defaultCenter] removeObserver:_runtimeErrorHandlingObserver];
            _runtimeErrorHandlingObserver = nil;

            //  登録したObserverを削除
            [self removeObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" context:SessionRunningAndDeviceAuthorizedContext];
            [self removeObserver:self forKeyPath:@"stillImageOutput.capturingStillImage" context:CapturingStillImageContext];
            [self removeObserver:self forKeyPath:@"movieFileOutput.recording" context:RecordingContext];
            [self removeObserver:self forKeyPath:@"videoDeviceInput.device.adjustingFocus" context:AdjustingFocusContext];
        });
        _isCameraOpened = NO;
    });
}

#pragma mark - Notification

//  カメラからの映像が大きく変化した時のイベントをNotificationで受ける
- (void)subjectAreaDidChange:(NSNotification*)notification{
    //  真ん中をcontinuesでフォーカス合わせるように（露出もcontinuesで）
    CGPoint devicePoint = CGPointMake(.5, .5);
    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

#pragma mark - kvo

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    //  contextで切り分ける
    if(context == CapturingStillImageContext){
        //  静止画撮影中フラグの変化
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeIsCapturingStillImage" userInfo:@{@"state":@(isCapturingStillImage)}];
        });
        
        if(isCapturingStillImage == NO){
            if(self.isReadyForTakePhoto){
                //  Shutter予約がある場合は撮影する
                if(_shutterReserveCount){
                    [self doTakePhoto];
                }
            }
        }
    } else if(context == RecordingContext){
        //  recordingStateの変化
        BOOL isRecording = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeIsRecordingVideo" userInfo:@{@"state":@(isRecording)}];
        });
    } else if(context == SessionRunningAndDeviceAuthorizedContext){
        //  カメラ利用許可フラグの変化を追従（準備が完了したかどうかという意味合いで使える）
        BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isRunning){
                //  開始イベント発行
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self dispatchEvent:@"open" userInfo:nil];
                });
            } else {
                //  終了イベント発行
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self dispatchEvent:@"close" userInfo:nil];
                });
            }
        });
    }else if(context == AdjustingFocusContext){
        //  フォーカスの変化
        BOOL isAdjustingFocus = [change[NSKeyValueChangeNewKey] boolValue];
        
        //  カーソルを消すとか表示するとか
        if(isAdjustingFocus == NO){
			dispatch_async(dispatch_get_main_queue(), ^{
				[self dispatchEvent:@"hideFocusCursor" userInfo:nil];
			});
            _focusViewShowHide = NO;
        } else if(_focusViewShowHide == NO){
            //  フォーカス開始で、かつfocusViewが表示されてない場合（continuesで呼ばれた場合となる）
            CGPoint focusPos;
            if(_videoDeviceInput.device.focusPointOfInterestSupported)
                focusPos = _videoDeviceInput.device.focusPointOfInterest;
            else
                focusPos = CGPointMake(0.5, 0.5);
            
            [self showFocusCursorWithPos:focusPos isContinuous:YES];
        }
        
        _adjustingFocus = isAdjustingFocus;
        
        if(_adjustingFocus == NO){
            if(self.isReadyForTakePhoto){
                //  Shutter予約がある場合は撮影する
                if(_shutterReserveCount){
                    [self doTakePhoto];
                }
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - utility

/// オートフォーカスオン
-(void)enableAutoFocus{
	_autoFocusEnabled = YES;
	dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *device = [_videoDeviceInput device];
        NSError *error = nil;
        if( [device lockForConfiguration:&error] ){
            if( [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]){
				device.focusMode = AVCaptureFocusModeContinuousAutoFocus;//  フォーカスモードを設定
            }
            [device unlockForConfiguration];//  unlock
        } else {
            NSLog(@"%@", error);
        }
    });
}

/// オートフォーカスオフ
// ビデオ撮影前に呼ぶと、純正と同じように、撮影中はオートフォーカスしないようになります
-(void)disableAutoFocus{
	_autoFocusEnabled = NO;
	dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *device = [_videoDeviceInput device];
        NSError *error = nil;
        if( [device lockForConfiguration:&error] ){
            if( [device isFocusModeSupported:AVCaptureFocusModeLocked]){
				device.focusMode = AVCaptureFocusModeLocked;//  フォーカスモードを設定
            }
            [device unlockForConfiguration];//  unlock
        } else {
            NSLog(@"%@", error);
        }
    });
}

/// 指定したポイントにフォーカスを合わせる
-(void)setFocusToPoint:(CGPoint)point{
	dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *device = [_videoDeviceInput device];
        NSError *error = nil;
        if([device lockForConfiguration:&error]){
            if([device isFocusPointOfInterestSupported] ){
                [device setFocusPointOfInterest:point];//  フォーカスを設定
            }
            if([device isExposurePointOfInterestSupported] ){
                [device setExposurePointOfInterest:point];//  露出モードを設定
            }
            
            [device unlockForConfiguration];//  unlock
        } else {
            NSLog(@"%@", error);
        }
    });
}



//  フォーカスをあわせる処理を実行するメソッド
- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange{
	void(^process)(void) = ^(){
		AVCaptureDevice *device = [_videoDeviceInput device];
        
        NSError *error = nil;
        if([device lockForConfiguration:&error]){
            //  フォーカスモードを設定
            if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode]){
                [device setFocusPointOfInterest:point];
                [device setFocusMode:focusMode];
            }
            
            //  露出モードを設定
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode]){
                [device setExposurePointOfInterest:point];
                [device setExposureMode:exposureMode];
            }
            
            [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectAreaChange];//  画面変化を追従するかの設定
            [device unlockForConfiguration];//  unlock
        } else {
            NSLog(@"%@", error);
        }
	};

	if( [NSThread isMainThread] ){
		dispatch_async( self.sessionQueue, process );
	} else {
		process();
	}
}


#pragma mark -

//  ユーザーがカメラ機能へのアクセスを許可するかどうか確認
- (void)checkDeviceAuthorizationStatus{
    NSString *mediaType = AVMediaTypeVideo;
    
    if(floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1){
        // iOS 6.1以前
        self.deviceAuthorized = YES;
    } else {
        // iOS 7.0以降
        [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
            if(granted){
                //  Granted access to mediaType
                self.deviceAuthorized = YES;
            } else {
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
}

- (void)applicationDidEnterBackground:(NSNotification*)notification{
    NSLog(@"applicationDidEnterBackground");
    if(_isCameraOpened){
        _lastOpenState = YES;
        
        //  画面消すためにここで送っておく
		dispatch_async(dispatch_get_main_queue(), ^{
			[self dispatchEvent:@"close" userInfo:nil];
		});
        
        //
        [self closeCamera];
    } else {
        _lastOpenState = NO;
	}
}

- (void)applicationWillEnterForeground:(NSNotification*)notification{
    NSLog(@"applicationWillEnterForeground");
    if(_lastOpenState){
        [self openCamera];
    }
}

#pragma mark - ClassMethod

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position{
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

- (BOOL)isSessionRunningAndDeviceAuthorized{
    //  ここの変化を使ってopen/closeを呼ぶ（使用許可とセッション状態）
    return [_session isRunning] && [self isDeviceAuthorized];
}

+ (NSSet*)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized{
    return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (BOOL)isReadyForTakePhoto{
    AVCaptureDevice *device =_videoDeviceInput.device;
    
    BOOL freeMemory = [CameraManager getFreeMemory]>10.0?YES:NO;
    
    if(_cameraMode == CMCameraModeStill)
        return !device.isAdjustingFocus && !_stillImageOutput.capturingStillImage && freeMemory;
    else
        return !device.isAdjustingFocus && !_movieFileOutput.recording && freeMemory;
}

#pragma mark - focus関連

- (void)showFocusCursorWithPos:(CGPoint)pos isContinuous:(BOOL)isContinuous{
    _focusViewShowHide = YES;
    
    //  とにかくイベントを送る
	dispatch_async(dispatch_get_main_queue(), ^{
		[self dispatchEvent:@"showFocusCursor" userInfo:@{ @"position":[NSValue valueWithCGPoint:pos], @"isContinuous":@(isContinuous) }];
	});
}

#pragma mark -

- (id)init{
    self = [super init];
    if(self){
        [self setup];
    }
    return self;
}

#pragma mark -

- (void)setFocusPoint:(CGPoint)pos{
    //
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    //  タッチした位置へのフォーカスをサポートするかチェック
    if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus])    {
        //  フォーカス合わせ始めたことにする
        _adjustingFocus = YES;
        
        [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:pos monitorSubjectAreaChange:YES];
        
        //  アニメーションスタート
        [self showFocusCursorWithPos:pos isContinuous:NO];
    }
}

- (void)setFlashMode:(CMFlashMode)flashMode{
    _flashMode = flashMode;
    
    //  デバイス側にも指定
    [self setDeviceFlashMode:_flashMode];
        
    //  イベント発行
	dispatch_async(dispatch_get_main_queue(), ^{
		[self dispatchEvent:@"didChangeFlashMode" userInfo:@{ @"mode":@(_flashMode) }];
	});
}

- (void)setDeviceFlashMode:(CMFlashMode)flashMode{
    AVCaptureDevice *device = _videoDeviceInput.device;
	
	if( [device hasFlash] == NO ){
		return;
	}
    
	void(^process)(void) = ^(){
		NSError *error = nil;
		if([device lockForConfiguration:&error]){
			switch(flashMode){
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
		} else {
			NSLog(@"error:%@", error);
		}
	};

	if( [NSThread isMainThread] ){
		dispatch_async( [self sessionQueue], process );
	} else {
		process();
	}
}

#pragma mark - IBAction

- (void)changeFlashMode{
    //  flashモードのボタンを押された（順に切り替える）
    self.flashMode = (_flashMode+1)%3;
}

//  撮影処理を内部的に呼ぶ場合はここ
- (void)doTakePhoto{
    //  静止画の時だけ状態によりブロック
    if(!self.isReadyForTakePhoto && _cameraMode == CMCameraModeStill){
        return;
	}
    
    //  カウントデクリメント
    if(_shutterReserveCount){
        _shutterReserveCount--;
	}
    
    if(_cameraMode == CMCameraModeStill){
        //  静止画撮影モード
//        NSLog(@"freeMemory:%f", [CameraManager getFreeMemory]);
        [self captureImage];
    } else {
        //  動画モード
        if(!_recordingProgressTimer)
            [self startVideoRec];//  動画撮影
        else
            [self stopVideoRec];//  録画中に押された場合は停止処理する
    }
}

//  シャッターボタンを押された
- (void)takePhoto{
    //  フォーカスに対応してないとき用の処理
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    if(!device.isFocusPointOfInterestSupported)
        _adjustingFocus = NO;
    
    //  ビデオモードの時は予約処理いらない
    if(_cameraMode == CMCameraModeVideo){
        _shutterReserveCount = 0;
    } else {
        //  フォーカスを合わせてる途中だったら予約処理にする
        if(!self.isReadyForTakePhoto){
            if(_shutterReserveCount<1){
                _shutterReserveCount++;
			}
            
            BOOL freeMemory = [CameraManager getFreeMemory]>10.0?YES:NO;
            if(freeMemory == NO){
                _shutterReserveCount = 0;
                return;
            }
        }
    }
    if(_shutterReserveCount == 0){
        [self doTakePhoto];
	}
}

//
- (void)rotateCameraPosition{
    //  回転させるときに一旦focusの表示消すように送る
    if(_focusViewShowHide){
		dispatch_async(dispatch_get_main_queue(), ^{
			[self dispatchEvent:@"hideFocusCursor" userInfo:nil];
		});
        _focusViewShowHide = NO;
    }
    
    dispatch_async([self sessionQueue], ^{
		AVCaptureDevice *currentVideoDevice = [_videoDeviceInput device];
		AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
		AVCaptureDevicePosition currentPosition = [currentVideoDevice position];
		
		switch(currentPosition){
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
            [self dispatchEvent:@"willChangeCameraFrontBack" userInfo:@{ @"position":@(preferredPosition)} ];
        });
        
        //  指定デバイスを探す
		AVCaptureDevice *videoDevice = [CameraManager deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
		
		[_session beginConfiguration];
		
        //  sessionから今のデバイスを外す
		[_session removeInput:[self videoDeviceInput]];
        
        //  sessionに追加するまえにpresetを変更
        NSString *lastPreset = _session.sessionPreset;
        if(preferredPosition == AVCaptureDevicePositionBack){
            if(_cameraMode == CMCameraModeStill){
                _session.sessionPreset = !_silentShutterMode?_sessionPresetForStill:_sessionPresetForSilentStill;
            } else {
                _session.sessionPreset = _sessionPresetForVideo;
			}
        } else {
            if(_cameraMode == CMCameraModeStill){
                _session.sessionPreset = !_silentShutterMode?_sessionPresetForFrontStill:_sessionPresetForSilentFrontStill;
			} else {
                _session.sessionPreset = _sessionPresetForFrontVideo;
			}
        }
        
        //  追加できるか調べて追加
		if ([_session canAddInput:videoDeviceInput]){
            //  変更できれば変更
			[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
			
            [self removeObserver:self forKeyPath:@"videoDeviceInput.device.adjustingFocus" context:AdjustingFocusContext];
            
			[_session addInput:videoDeviceInput];
			_videoDeviceInput = videoDeviceInput;
            
            [self addObserver:self forKeyPath:@"videoDeviceInput.device.adjustingFocus" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:AdjustingFocusContext];
		} else {
            _session.sessionPreset = lastPreset;//  sessionに追加するまえにpresetを変更
			[_session addInput:_videoDeviceInput];//  ダメな場合戻す
		}
		
		[_session commitConfiguration];
		
        //  イベント発行
		dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeCameraFrontBack" userInfo:@{ @"position":@(_videoDeviceInput.device.position)}];
		});
	});
}

#pragma mark - orientation utility

- (UIImageOrientation)currentImageOrientation{
    AVCaptureDevice *device = _videoDeviceInput.device;
    
    BOOL isFront = device.position == AVCaptureDevicePositionFront?YES:NO;
    UIImageOrientation imageOrientation = UIImageOrientationLeft;
    switch (_orientation){
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
            imageOrientation = UIImageOrientationRight;
            break;
    }
    
    return imageOrientation;
}

- (AVCaptureVideoOrientation)currentVideoOrientation{
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationPortrait;
    switch (_orientation){
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

- (void)captureImage{
    //  キャプチャー処理
	__weak typeof(self) weakSelf = self;
    if(_silentShutterMode){
        //  サイレントモードの時は別処理
        [self captureCurrentPreviewImageForAnimation:NO completion:^(UIImage *image) {
			// フロントカメラで撮影したものならフリップ
//            AVCaptureDevice *device = _videoDeviceInput.device;
//            BOOL isFront = device.position == AVCaptureDevicePositionFront?YES:NO;
//			UIImage* flipped_img = [UIImage imageWithCGImage:image.CGImage scale:1.0f orientation:isFront?UIImageOrientationLeftMirrored:UIImageOrientationRight];
            
			NSData* jpegData = UIImageJPEGRepresentation(image, 0.8);
			[weakSelf saveToCameraRoll:jpegData];// カメラロールに保存
            [weakSelf capturedImage:image originalJpegData:jpegData error:nil];
        }];
    } else {
		// 先にstillImageOutputのほうで撮影して、完了時に画面キャプチャしたほうが、映像のギャップが少ないです
		[self captureStillWithCompletion:^(NSData *jpegData, NSError *error) {
			[weakSelf captureCurrentPreviewImageForAnimation:NO completion:^(UIImage *imageForAnimation) {
				[weakSelf capturedImage:imageForAnimation originalJpegData:jpegData error:error];
			}];
		}];
    }
}


- (void)captureStillWithCompletion:(void(^)(NSData *jpegData, NSError *error))completion{
	__weak typeof(self) weakSelf = self;
    dispatch_async(_sessionQueue, ^{
        
		//  orientationを設定
		[[_stillImageOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[weakSelf currentVideoOrientation]];
				
		//  撮影処理
		[_stillImageOutput captureStillImageAsynchronouslyFromConnection:[_stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
			if( error ){
				completion( nil, error );
				return;
			}
			
			NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
			[weakSelf saveToCameraRoll:imageData];// カメラロールに保存
			completion(imageData, nil);
		}];
	});
}


/// カメラロールに保存
// jpegStillImageNSDataRepresentation したデータをそのまま渡しましょう。
-(void)saveToCameraRoll:(NSData*)data{
	if(_autoSaveToCameraroll){
		SaveToCameraRollOperation* op = [[SaveToCameraRollOperation alloc] initWithData:data];
		[_saveToCameraRoll_queue addOperation:op];
    }
}


- (void)capturedImage:(UIImage*)originalImage originalJpegData:(NSData*)jpegData error:(NSError*)error{
    //  イベント発行
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dispatchEvent:@"didCapturedImage" userInfo:@{ @"image":originalImage, @"originalJpegData":jpegData }];
    });
}

#pragma mark - video

- (void)setupTorch{
    AVCaptureDevice *device = _videoDeviceInput.device;
    if([device hasFlash]){
        //  フラッシュの設定
        NSError *error = nil;
        if (![device lockForConfiguration:&error]){
            NSLog(@"Error locking for configuration: %@", error);
        }
        
        //  フラッシュの準備（上記のロックをかけてからでないと処理できないっぽい）
        if(_flashMode == CMFlashModeAuto && [device hasTorch]){
            device.torchMode = AVCaptureTorchModeAuto;//  自動
        } else if(_flashMode == CMFlashModeOn && [device hasTorch]){
            device.torchMode = AVCaptureTorchModeOn;//  ON
        } else if([device hasTorch]){
            device.torchMode = AVCaptureTorchModeOff;//  OFF
        }
        [device unlockForConfiguration];
    }
}

- (void)offTorch{
    AVCaptureDevice *device = _videoDeviceInput.device;
    if([device hasFlash]){
        [device lockForConfiguration:nil];
        [device setTorchMode:AVCaptureTorchModeOff];
        [device unlockForConfiguration];
    }
}

- (NSString*)makeTempMovieFileName{
    NSString *uuidString = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:@"%@.m4v", uuidString];
}

- (void)startVideoRec{
    //  event発行
	dispatch_async(dispatch_get_main_queue(), ^{
		[self dispatchEvent:@"willStartVideoRecording" userInfo:nil];
	});
    dispatch_async([self sessionQueue], ^{
		if(!_movieFileOutput.isRecording){
            //  録画開始
			_lockInterfaceRotation = YES;
			
			[self disableAutoFocus];// 純正に合わせるため、オートフォーカスをオフに
			
			if ([[UIDevice currentDevice] isMultitaskingSupported]){
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
                [self startRecordingProgressTimer];
                [self dispatchEvent:@"didStartVideoRecording" userInfo:nil];//event発行
            });
        }
	});
}

- (void)stopVideoRec{
    dispatch_async([self sessionQueue], ^{
        [_movieFileOutput stopRecording];
    });
}

- (void)startRecordingProgressTimer{
    if(_recordingProgressTimer)
        [self stopRecordingProgressTimer];
    
    _recordingProgressTimer = [NSTimer timerWithTimeInterval:1.0/10.0 target:self selector:@selector(doProgressRecording:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_recordingProgressTimer forMode:NSRunLoopCommonModes];
}

- (void)stopRecordingProgressTimer{
    if(_recordingProgressTimer){
        [_recordingProgressTimer invalidate];
        _recordingProgressTimer = nil;
    }
}

- (void)doProgressRecording:(NSTimer*)timer{
    if(_recordingProgressTimer == timer){
        //  残り時間のチェック
        if(self.remainRecordTime<0.0){
            //  終了
            [self stopVideoRec];
        } else {
            //  イベント発行
			dispatch_async(dispatch_get_main_queue(), ^{
				[self dispatchEvent:@"recordingVideo" userInfo:@{ @"time":@(self.recordedTime), @"remainTime":@(self.remainRecordTime)}];
			});
        }
    }
}

//  tmpFileはもういらないよの通知
- (void)removeTempMovieFile:(NSURL*)tmpURL{
    NSString *path = tmpURL.path;
    //
    if([_tmpMovieSavePathArray containsObject:path]){
        //  まだ消してはいけない
        //  リストからは消しておく
        [_tmpMovieSavePathArray removeObject:path];
    } else {
        //  もう処理が終わってるらしいので消す
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        NSLog(@"removeFile:%@", path);
    }
}

//
- (NSTimeInterval)recordedTime{
    CMTime time = _movieFileOutput.recordedDuration;
    return CMTimeGetSeconds(time);
}

- (NSTimeInterval)remainRecordTime{
    return _videoDuration - self.recordedTime;
}


/// 動画のパスから動画サムネイルのUIImageを作成
// lastFrame が YES だと最後のフレームをキャプチャ。NO だと最初のフレームをキャプチャ
// http://stackoverflow.com/questions/19105721/thumbnailimageattime-now-deprecated-whats-the-alternative
- (UIImage*)createThumbnailImage:(NSURL*)movieURL lastFrame:(BOOL)lastFrame{
	AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:movieURL options:nil];
    if ([asset tracksWithMediaCharacteristic:AVMediaTypeVideo]) {
        AVAssetImageGenerator *imageGen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        [imageGen setAppliesPreferredTrackTransform:YES];
		
		Float64 seconds;
		if( lastFrame ){
			seconds = CMTimeGetSeconds([asset duration]);
		} else {
			seconds = 0;
		}
        CMTime midpoint =   CMTimeMakeWithSeconds( seconds, 600 );
        NSError* error = nil;
        CMTime actualTime;
		
        CGImageRef halfWayImageRef = [imageGen copyCGImageAtTime:midpoint actualTime:&actualTime error:&error];
		
        if (halfWayImageRef != NULL) {
            UIImage* myImage = [[UIImage alloc]initWithCGImage:halfWayImageRef];
            CGImageRelease(halfWayImageRef);
            return myImage;
        }
    }
    return nil;
}

#pragma mark - AVCaptureDeviceFileOutputDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error{
    BOOL recordedSuccessfully = YES;
    if ([error code] != noErr){
        id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value){
            recordedSuccessfully = [value boolValue];
        }
    }
    
	_lockInterfaceRotation = NO;
	
	UIBackgroundTaskIdentifier backgroundRecordingID = _backgroundRecordingID;
    _backgroundRecordingID = UIBackgroundTaskInvalid;

    [self stopRecordingProgressTimer];//  プログレスのタイマー止める
    [self offTorch];//  照明必ず消す
    
    if(recordedSuccessfully == NO){
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didFinishedVideoRecording" userInfo:nil ];
        });
    } else {
		// サムネイル作成
//		MPMoviePlayerController *player = [[MPMoviePlayerController alloc] initWithContentURL:outputFileURL];
//		UIImage  *thumbnail = [player thumbnailImageAtTime:1.0 timeOption:MPMovieTimeOptionNearestKeyFrame];// deprecated
		UIImage* firstFrame_img = [self createThumbnailImage:outputFileURL lastFrame:NO];
		UIImage* lastFrame_img = [self createThumbnailImage:outputFileURL lastFrame:YES];
		
        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didFinishedVideoRecording" userInfo:@{ @"movieURL":outputFileURL, @"firstFrame_img":firstFrame_img, @"lastFrame_img":lastFrame_img } ];
        });
        
        //  保存処理
        if(_autoSaveToCameraroll){
            dispatch_async(_saveQueue, ^{
                [[[ALAssetsLibrary alloc] init] writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
                    if (error)
                        NSLog(@"%@", error);
                    
                    NSLog(@"saveVideo to CameraRoll Finished:%@", outputFileURL);
                    
                    if([_tmpMovieSavePathArray containsObject:outputFileURL.path]){
                        //  まだ消してはいけない
                        //  リストからは消しておく
                        [_tmpMovieSavePathArray removeObject:outputFileURL.path];
                    } else {
                        //  もう処理が終わってるらしいので消す
                        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
                        
                        NSLog(@"removeFile:%@", outputFileURL.path);
                    }
                    
                    if (backgroundRecordingID != UIBackgroundTaskInvalid)
                        [[UIApplication sharedApplication] endBackgroundTask:backgroundRecordingID];
                }];
            });
        }
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection{
    if(_captureCompletion){
        // イメージバッファの取得
        CVImageBufferRef    buffer;
        buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // イメージバッファのロック
        CVPixelBufferLockBaseAddress(buffer, 0);
        
        // イメージバッファ情報の取得
        uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
        size_t width = CVPixelBufferGetWidth(buffer);
        size_t height = CVPixelBufferGetHeight(buffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
        
        // ビットマップコンテキストの作成
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef cgContext = CGBitmapContextCreate(base, width, height, 8, bytesPerRow, colorSpace,kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGColorSpaceRelease(colorSpace);
        
        // 画像の作成
        CGImageRef cgImage = CGBitmapContextCreateImage(cgContext);
        AVCaptureDevice *device = _videoDeviceInput.device;
        BOOL isFront = device.position == AVCaptureDevicePositionFront?YES:NO;
        UIImage *image = [UIImage imageWithCGImage:cgImage scale:1.0f orientation:_isImageForAnimation?(isFront?UIImageOrientationLeftMirrored:UIImageOrientationRight):[self currentImageOrientation]];
		NSLog( @"%d", image.imageOrientation );
        CGImageRelease(cgImage);
        CGContextRelease(cgContext);
        
        // イメージバッファのアンロック
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        
        //  現在の画像をキャッシュする
        _captureCompletion(image);
        _captureCompletion = nil;
    }
}

#pragma mark - capturePreviewImage

- (void)captureCurrentPreviewImageForAnimation:(BOOL)forAnimation completion:(void(^)(UIImage *image))completion
{
    _isImageForAnimation = forAnimation;
    self.captureCompletion = completion;
}

#pragma mark - cameraMode

//  カメラモードを切り替える
- (void)toggleCameraMode{
    if(_cameraMode == CMCameraModeStill){
        self.cameraMode = CMCameraModeVideo;
        [self offTorch];
    } else {
        self.cameraMode = CMCameraModeStill;
        self.flashMode = _flashMode;
    }
}

- (void)setCameraMode:(CMCameraMode)cameraMode{
    _cameraMode = cameraMode;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self dispatchEvent:@"willChangeCameraMode" userInfo:@{ @"mode":@(_cameraMode)} ];//  イベント発行
	});
    dispatch_async(_sessionQueue, ^{
        //  sessionpreset変更
        AVCaptureDevice *device = _videoDeviceInput.device;
		      
		NSError* error;
		[device lockForConfiguration:&error];
				
        if(_cameraMode == CMCameraModeStill){
            //  静止画モードに切り替えるとき
            //  outputの設定
            if([_session.outputs containsObject:_movieFileOutput])  //  動画で使うoutputを抜く
                [_session removeOutput:_movieFileOutput];
            
            if(![_session.outputs containsObject:_stillImageOutput] && [_session canAddOutput:_stillImageOutput])   //  静止画撮影用
                [_session addOutput:_stillImageOutput];
            
            if(![_session.outputs containsObject:_videoDataOutput] && [_session canAddOutput:_videoDataOutput])     //  サイレント撮影用
                [_session addOutput:_videoDataOutput];
            
            //  sessionPreset変更する
            if(device.position == AVCaptureDevicePositionFront){
                //  フロントカメラの時
                if([device supportsAVCaptureSessionPreset:_sessionPresetForFrontStill])
                    _session.sessionPreset = !_silentShutterMode?_sessionPresetForFrontStill:_sessionPresetForSilentFrontStill;
                else
                    _session.sessionPreset = AVCaptureSessionPresetPhoto;
            } else {
                //  リアカメラの時
                if([device supportsAVCaptureSessionPreset:_sessionPresetForStill])
                    _session.sessionPreset = !_silentShutterMode?_sessionPresetForStill:_sessionPresetForSilentStill;
                else
                    _session.sessionPreset = AVCaptureSessionPresetPhoto;
            }
        } else {
            //  動画モードに切り替えるとき
            
            //  outputの設定
            if([_session.outputs containsObject:_stillImageOutput])   //  静止画撮影用をはずす
                [_session removeOutput:_stillImageOutput];
            
            if([_session.outputs containsObject:_videoDataOutput])     //  サイレント撮影用をはずす
                [_session removeOutput:_videoDataOutput];
            
            if(![_session.outputs containsObject:_movieFileOutput] && [_session canAddOutput:_movieFileOutput])  //  動画で使うoutputを追加
                [_session addOutput:_movieFileOutput];
			
			//  動画用にオーディオデバイスも取得(このタイミングでマイクへのアクセスの許可リクエストアラートが表示されます)
			NSError* error;
			AVCaptureDevice *audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
			AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
			if( error ){
				NSLog(@"%@", error);
			}
			if([_session canAddInput:audioDeviceInput]){
				[_session addInput:audioDeviceInput];
			}

            //  sessionPreset変更する
            if(device.position == AVCaptureDevicePositionFront){
                //  フロントカメラの時
                if([device supportsAVCaptureSessionPreset:_sessionPresetForFrontVideo])
                    _session.sessionPreset = _sessionPresetForFrontVideo;
                else
                    _session.sessionPreset = AVCaptureSessionPresetHigh;
            } else {
                //  リアカメラの時
                if([device supportsAVCaptureSessionPreset:_sessionPresetForVideo])
                    _session.sessionPreset = _sessionPresetForVideo;
                else
                    _session.sessionPreset = AVCaptureSessionPresetHigh;
            }
        }
		[device unlockForConfiguration];

        //  イベント発行
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dispatchEvent:@"didChangeCameraMode" userInfo:@{ @"mode":@(_cameraMode)} ];
        });
    });
}




#pragma mark - silentShutterMode

- (void)setSilentShutterMode:(BOOL)silentShutterMode{
    _silentShutterMode = silentShutterMode;
    
    if(_cameraMode == CMCameraModeStill){
		dispatch_async(dispatch_get_main_queue(), ^{
			[self dispatchEvent:@"willChangeSilentMode" userInfo:nil];
		});
        
        dispatch_async(_sessionQueue, ^{
            AVCaptureDevice *device = _videoDeviceInput.device;
            if(device.position == AVCaptureDevicePositionBack){
                _session.sessionPreset = !_silentShutterMode?_sessionPresetForStill:_sessionPresetForSilentStill;
            } else {
                _session.sessionPreset = !_silentShutterMode?_sessionPresetForFrontStill:_sessionPresetForSilentFrontStill;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dispatchEvent:@"didChangeSilentMode" userInfo:nil];
            });
        });
    }
}

@dynamic hasFlash;
- (BOOL)hasFlash
{
    AVCaptureDevice *device = _videoDeviceInput.device;
    return [device hasFlash];
}

@dynamic position;
- (AVCaptureDevicePosition)position
{
    return _videoDeviceInput.device.position;
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
