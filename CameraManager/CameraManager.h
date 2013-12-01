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
//      flashButton、shutterButton、cameraFrontBackButton、focusFrameViewはそれぞれ別で用意したものをIntefaceBuilderでつなぐかプログラムでつなぐかして使う
//      上記のパーツは、一部iPhoneの傾きに応じて回転させる処理や表示/非表示、位置の変更など行うのでつなぎこむ必要がある
//      同様に、changeFlashMode:、takePhoto:、rotateCameraPosition:もIBActionをつなぐ、もしくはプログラムでつないで使う前提
//      focusViewは、各PreviewViewに入ってる前提で、Array対応

//  無音シャッター機能追加
//      silentShutterModeをYESにすると無音カメラ状態になる。ただし、プレビューに使っている画像を保存するため解像度は低い。
//      無音状態で解像度を高める方法があるのかについては深く調べてない（軽く調べた感じ、難しい気がした）

#import <GPUImage/GPUImage.h>

enum CMFlashMode    //この順でモードが切り替わる
{
    FLASH_MODE_AUTO = 0,
    FLASH_MODE_OFF,
    FLASH_MODE_ON
};


#pragma mark - delegate protocol

@class CameraManager;

@protocol CameraManagerDelegate <NSObject>
- (void)cameraManager:(CameraManager*)sender didCapturedImage:(UIImage*)image;
- (void)cameraManager:(CameraManager *)sender didChangeAdjustingFocus:(BOOL)isAdjustingFocus devide:(AVCaptureDevice*)device;
@end

#pragma mark - interface

@interface CameraManager : NSObject

//  StoryBoardでつなぎ込むGUIパーツ
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UIButton *shutterButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraFrontBackButton;

//  設定パラメータ
@property (strong, nonatomic) NSString *flashAutoImageName;
@property (strong, nonatomic) NSString *flashOffmageName;
@property (strong, nonatomic) NSString *flashOnImageName;
@property (assign, nonatomic) NSInteger flashMode;
@property (assign, nonatomic) NSTimeInterval delayTimeForFlash;
@property (assign, nonatomic) BOOL autoSaveToCameraroll;
@property (assign, nonatomic) float jpegQuality;
@property (assign, nonatomic) BOOL silentShutterMode;

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


//  Filter
@property (readonly, nonatomic) NSArray *filterNameArray;

//  delegate
@property (weak, nonatomic) id <CameraManagerDelegate> delegate;

//  IBAction
- (IBAction)changeFlashMode:(id)sender;     //  フラッシュのモードを変える
- (IBAction)takePhoto:(id)sender;           //  写真を撮る
- (IBAction)rotateCameraPosition:(id)sender;//  カメラの前と後ろを入れ替える

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

@end
