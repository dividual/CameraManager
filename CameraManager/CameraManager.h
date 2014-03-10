//
//  CameraView.h
//  blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

//  GPUImageを使わずに、リアルタイムエフェクトなしバージョンに切り替え（2014/03/05）

@class PreviewView;

typedef NS_ENUM(NSInteger, CMFlashMode)
{
    CMFlashModeAuto = 0,
    CMFlashModeOff = 1,
    CMFlashModeOn = 2
};

typedef NS_ENUM(NSInteger, CMCameraMode)
{
    CMCameraModeStill = 0,
    CMCameraModeVideo = 1
};

#pragma mark - interface

@interface CameraManager : NSObject

//  設定パラメータ
@property (assign, nonatomic) CMFlashMode flashMode;
@property (assign, nonatomic) NSTimeInterval delayTimeForFlash;
@property (assign, nonatomic) BOOL autoSaveToCameraroll;
@property (assign, nonatomic) float jpegQuality;
@property (assign, nonatomic) BOOL silentShutterMode;

//  プレビューや撮影の解像度設定（SessionPreset）
@property (strong, nonatomic) NSString *sessionPresetForStill;      //  写真撮影用（リアカメラ）
@property (strong, nonatomic) NSString *sessionPresetForVideo;      //  動画撮影用（リアカメラ）

@property (strong, nonatomic) NSString *sessionPresetForFrontStill; //  写真撮影用（フロントカメラ
@property (strong, nonatomic) NSString *sessionPresetForFrontVideo; //  写真撮影用（リアカメラ

@property (strong, nonatomic) NSString *sessionPresetForSilentStill;//  無音カメラ（リアカメラ）
@property (strong, nonatomic) NSString *sessionPresetForSilentFrontStill;//  無音カメラ（フロントカメラ）

//  動画に関すること
@property (readonly, nonatomic) AVCaptureSession *session;
@property (assign, nonatomic) CMCameraMode cameraMode;              //  写真モードか動画モードか
@property (assign, nonatomic) NSTimeInterval videoDuration;         //  録画時間（一回の録画での最大長さ）
@property (readonly, nonatomic) NSTimeInterval recordedTime;        //  録画済みの時間
@property (readonly, nonatomic) NSTimeInterval remainRecordTime;    //  録画残り時間

//  その他
@property (readonly, nonatomic) BOOL hasFlash;                      //  内部で判定してるフラッシュもってるかどうか
@property (readonly, nonatomic) BOOL isChooseFilterMode;            //  フィルター選択画面の状態かどうか
@property (readonly, nonatomic) BOOL isCameraOpened;                //  カメラを開いてるかどうか
@property (readonly, nonatomic) AVCaptureDevicePosition position;   //  カメラが前か後ろか

//  ズーム対応
@property (assign, nonatomic) CGFloat zoomScale;                    //  ズームのスケールを入れる 1.0 ~
@property (readonly, nonatomic) CGFloat maxZoomScale;               //  ズームの最大スケール

//  操作系
- (void)changeFlashMode;                                            //  フラッシュのモードを変える（順に切り替える）
- (void)takePhoto;                                                  //  写真を撮る
- (void)rotateCameraPosition;                                       //  カメラの前と後ろを入れ替える（toggle）

//  インスタンス（シングルトン化した）
+ (CameraManager*)sharedManager;

//  操作メソッド
- (void)openCamera;                                                 //  sessionPresetForStill等の設定をひと通りしてから呼ぶこと
- (void)closeCamera;                                                //  カメラを使うのをやめるとき
- (void)setFocusPoint:(CGPoint)pos;                                 //  フォーカスを合わせるとき（view内の座標で指定）
- (void)toggleCameraMode;                                           //  カメラモードを切り替える
- (void)removeTempMovieFile:(NSURL*)tmpURL;                         //  tmpFileはもういらないよの通知（動画についての処理）

@end
