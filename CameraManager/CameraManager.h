//
//  CameraView.h
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>

//  GPUImageを活用し、カメラの撮影機能を実装
//      delegateで管理するイベント、blockで管理するイベントがある
//      GPUImageの組み込みには、CococaPodを使うことに。


//  2013/12/01
//  変更の内容
//      GPUImageViewのサブクラスとして作ったのをやめて、Managerクラスとして再構成
//      flashButton、shutterButton、cameraFrontBackButton、focusFrameViewはそれぞれ別で用意したものをIntefaceBuilderでつなぐかプログラムでつなぐかして使う（名称変更してArray化してある）
//      上記のパーツは、一部iPhoneの傾きに応じて回転させる処理や表示/非表示、位置の変更など行うのでつなぎこむ必要がある
//      同様に、changeFlashMode:、takePhoto:、rotateCameraPosition:もIBActionをつなぐ、もしくはプログラムでつないで使う前提

//  無音シャッター機能追加
//      silentShutterModeをYESにすると無音カメラ状態になる。ただし、プレビューに使っている画像を保存するため解像度は低い。
//      無音状態で解像度を高める方法があるのかについては深く調べてない（軽く調べた感じ、難しい気がした）

//  エフェクト選択画面を実装してみる

//  2014/01/10
//  変更の内容
//      動画撮影機能の追加
//      それに伴ういくつかのdelegate追加など

#import <GPUImage/GPUImage.h>

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


#pragma mark - delegate protocol

@class CameraManager;

@protocol CameraManagerDelegate <NSObject>

@optional
- (void)cameraManager:(CameraManager*)sender didCapturedImage:(UIImage*)image;
- (void)cameraManager:(CameraManager*)sender didPlayShutterSoundWithImage:(UIImage*)image;
- (void)cameraManager:(CameraManager*)sender didChangeAdjustingFocus:(BOOL)isAdjustingFocus devide:(AVCaptureDevice*)device;
- (void)cameraManager:(CameraManager*)sender didChangeDeviceOrientation:(UIDeviceOrientation)orientation;
- (void)cameraManager:(CameraManager*)sender didChangeFilter:(NSString*)filterName;

- (void)cameraManagerWillStartRecordVideo:(CameraManager*)sender;
- (void)cameraManager:(CameraManager*)sender didRecordMovie:(NSURL*)tmpFileURL;
- (void)cameraManager:(CameraManager*)sender recordingTime:(NSTimeInterval)recordedTime remainTime:(NSTimeInterval)remainTime;

- (BOOL)cameraManager:(CameraManager*)sender shouldChangeShutterButtonImageTo:(NSString*)imageName;

@end

#pragma mark - interface

@interface CameraManager : NSObject

//  設定パラメータ
@property (strong, nonatomic) NSString *flashAutoImageName;
@property (strong, nonatomic) NSString *flashOffmageName;
@property (strong, nonatomic) NSString *flashOnImageName;
@property (strong, nonatomic) NSString *stillShutterButtonImageName;
@property (strong, nonatomic) NSString *videoShutterButtonImageName;
@property (strong, nonatomic) NSString *videoStopButtonImageName;

@property (assign, nonatomic) CMFlashMode flashMode;
@property (assign, nonatomic) NSTimeInterval delayTimeForFlash;
@property (assign, nonatomic) BOOL autoSaveToCameraroll;
@property (assign, nonatomic) float jpegQuality;
@property (assign, nonatomic) BOOL silentShutterMode;

@property (strong, nonatomic) NSString *sessionPresetForStill;
@property (strong, nonatomic) NSString *sessionPresetForVideo;

@property (strong, nonatomic) NSString *sessionPresetForFrontStill;
@property (strong, nonatomic) NSString *sessionPresetForFrontVideo;


@property (assign, nonatomic) CMCameraMode cameraMode;
@property (assign, nonatomic) NSTimeInterval videoDuration;
@property (readonly, nonatomic) NSTimeInterval recordedTime;      //  録画済みの時間
@property (readonly, nonatomic) NSTimeInterval remainRecordTime;  //  録画残り時間

@property (readonly, nonatomic) GPUImageStillCamera *stillCamera;
@property (readonly, nonatomic) BOOL hasFlash;

//  GPUImageViewをつなぎこんで使う前提
@property (readonly, nonatomic) NSArray *previewViews;

- (void)addPreviewView:(GPUImageView*)view;
- (void)addPreviewViewsFromArray:(NSArray*)viewsArray;
- (void)removeAllPreviewViews;
- (void)removePreviewView:(GPUImageView*)view;

//  FocusViewをつなぎこんで使う
@property (readonly, nonatomic) NSArray *focusViews;

- (void)addFocusView:(UIView*)view;
- (void)addFocusViewsFromArray:(NSArray*)viewsArray;
- (void)removeAllFocusViews;
- (void)removeFocusView:(UIView*)view;

//  flashButtonをつなぎこんで使う
@property (readonly, nonatomic) NSArray *flashButtons;

- (void)addFlashButton:(UIButton*)button;
- (void)addFlashButtonsFromArray:(NSArray*)buttonsArray;
- (void)removeAllFlashButtons;
- (void)removeFlashButton:(UIButton*)button;

//  shutterButtonをつなぎこんで使う
@property (readonly, nonatomic) NSArray *shutterButtons;

- (void)addShutterButton:(UIButton*)button;
- (void)addShutterButtonsFromArray:(NSArray*)buttonsArray;
- (void)removeAllShutterButtons;
- (void)removeShutterButton:(UIButton*)button;

//  cameraRotateButtonをつなぎこんで使う
@property (readonly, nonatomic) NSArray *cameraRotateButtons;

- (void)addCameraRotateButton:(UIButton*)button;
- (void)addCameraRotateButtonsFromArray:(NSArray*)buttonsArray;
- (void)removeAllCameraRotateButtons;
- (void)removeCameraRotateButton:(UIButton*)button;

//  button類の状態アップデート
- (void)updateButtons;

//  Filter
@property (readonly, nonatomic) NSArray *filterNameArray;

//  delegate
@property (weak, nonatomic) id <CameraManagerDelegate> delegate;

//
@property (readonly, nonatomic) BOOL isChooseFilterMode;
@property (readonly, nonatomic) BOOL isCameraOpened;


//  操作系
- (void)changeFlashMode:(id)sender;     //  フラッシュのモードを変える
- (void)takePhoto:(id)sender;           //  写真を撮る
- (void)rotateCameraPosition:(id)sender;//  カメラの前と後ろを入れ替える

//  インスタンス（シングルトン化した）
+ (CameraManager*)sharedManager;

//  操作メソッド

//  一通りセットアップしたら呼ぶコマンド
- (void)openCamera;

//  カメラを使うのをやめるとき
- (void)closeCamera;

//  フォーカスを合わせるとき
- (void)setFocusPoint:(CGPoint)pos inView:(GPUImageView*)view; //view内の座標値で指定

//  フィルターを選択
- (void)setFilterWithName:(NSString*)name;

//  プレビューに使ってる画像を即座に返す
- (UIImage*)captureCurrentPreviewImage;

//  エフェクト一覧画面を表示するための画面を作る（指定するGPUImageViewはprevieViewsとして追加済みでないとダメ）
- (void)showChooseEffectInPreviewView:(GPUImageView*)previewView;

//  エフェクト選択モードを終了
- (void)dissmissChooseEffect;

//  カメラモードを切り替える
- (void)toggleCameraMode;

//  tmpFileはもういらないよの通知
- (void)removeTempMovieFile:(NSURL*)tmpURL;


@end
