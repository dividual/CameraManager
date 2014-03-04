//
//  CameraView.h
//  blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>

//  GPUImageを活用し、カメラの撮影機能を実装
//      delegateで管理するイベント、blockで管理するイベントがある
//      GPUImageの組み込みには、CococaPodを使うことに。

@class GPUImage;
@class GPUImageStillCamera;
@class GPUImageView;
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


#pragma mark - delegate protocol

@class CameraManager;

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

//  動画に関すること
@property (assign, nonatomic) CMCameraMode cameraMode;              //  写真モードか動画モードか
@property (assign, nonatomic) NSTimeInterval videoDuration;         //  録画時間（一回の録画での最大長さ）
@property (readonly, nonatomic) NSTimeInterval recordedTime;        //  録画済みの時間
@property (readonly, nonatomic) NSTimeInterval remainRecordTime;    //  録画残り時間

//  その他
@property (readonly, nonatomic) GPUImageStillCamera *stillCamera;   //  内部で使ってるGPUImageStillCamera
@property (readonly, nonatomic) BOOL hasFlash;                      //  内部で判定してるフラッシュもってるかどうか
@property (readonly, nonatomic) BOOL isChooseFilterMode;            //  フィルター選択画面の状態かどうか
@property (readonly, nonatomic) BOOL isCameraOpened;                //  カメラを開いてるかどうか

//  Filter
@property (readonly, nonatomic) NSArray *filterNameArray;           //  内部で設定してるフィルターの名前配列
@property (readonly, nonatomic) NSInteger currentFilterIndex;       //  現在のフィルターIndex
@property (readonly, nonatomic) NSString *currentFilterName;        //  現在のフィルター名前

//  ズーム対応
@property (assign, nonatomic) CGFloat zoomScale;                    //  ズームのスケールを入れる 1.0 ~
@property (readonly, nonatomic) CGFloat maxZoomScale;               //  ズームの最大スケール

//  プレビュー画面
- (void)addPreviewView:(PreviewView*)previewView;                  //  プレビュー画面の追加
- (void)removePreviewView:(PreviewView*)previewView;               //  プレビュー画面を消す

//  操作系
- (void)changeFlashMode;                                            //  フラッシュのモードを変える
- (void)takePhoto;                                                  //  写真を撮る
- (void)rotateCameraPosition;                                       //  カメラの前と後ろを入れ替える

//  インスタンス（シングルトン化した）
+ (CameraManager*)sharedManager;


//  操作メソッド

- (void)openCamera;                                                 //  sessionPresetForStill等の設定をひと通りしてから呼ぶこと
- (void)closeCamera;                                                //  カメラを使うのをやめるとき

- (void)setFocusPoint:(CGPoint)pos inView:(GPUImageView*)view;      //  フォーカスを合わせるとき（view内の座標で指定）
- (void)setFilterWithName:(NSString*)name;                          //  フィルターを選択
- (UIImage*)captureCurrentPreviewImage;                             //  プレビューに使ってる画像を即座に返す
- (void)showChooseEffectInPreviewView:(PreviewView*)previewView;   //  エフェクト一覧画面を表示するための画面を作る
- (void)dissmissChooseEffect;                                       //  エフェクト選択モードを終了
- (void)toggleCameraMode;                                           //  カメラモードを切り替える
- (void)removeTempMovieFile:(NSURL*)tmpURL;                         //  tmpFileはもういらないよの通知


@end
