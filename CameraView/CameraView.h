//
//  CameraView.h
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>

//  GPUImageを活用し、カメラの撮影機能を実装したView
//      delegateで管理するイベント、blockで管理するイベントがある
//      GPUImageの組み込み時には、User Header PathにGPUImage/frameworkを追加する必要あります

#import <GPUImage/GPUImage.h>

enum CVFlashMode    //この順でモードが切り替わる
{
    FLASH_MODE_AUTO = 0,
    FLASH_MODE_OFF,
    FLASH_MODE_ON
};


#pragma mark - delegate protocol

@class CameraView;

@protocol CameraViewDelegate <NSObject>
- (void)cameraView:(CameraView*)sender didCapturedImage:(UIImage*)image;
- (void)cameraView:(CameraView *)sender didChangeAdjustingFocus:(BOOL)isAdjustingFocus devide:(AVCaptureDevice*)device;
@end

#pragma mark - interface

@interface CameraView : GPUImageView

//  StoryBoardでつなぎ込むGUIパーツ
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UIButton *shutterButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraFrontBackButton;
@property (weak, nonatomic) IBOutlet UIImageView *focusFrameView;

//  設定パラメータ
@property (strong, nonatomic) NSString *flashAutoImageName;
@property (strong, nonatomic) NSString *flashOffmageName;
@property (strong, nonatomic) NSString *flashOnImageName;
@property (assign, nonatomic) NSInteger flashMode;
@property (assign, nonatomic) NSTimeInterval delayTimeForFlash;
@property (assign, nonatomic) BOOL autoSaveToCameraroll;
@property (assign, nonatomic) float jpegQuality;

//  Filter
@property (readonly, nonatomic) NSArray *filterNameArray;

//  delegate
@property (weak, nonatomic) id <CameraViewDelegate> delegate;

//  IBAction
- (IBAction)changeFlashMode:(id)sender;     //  フラッシュのモードを変える
- (IBAction)takePhoto:(id)sender;           //  写真を撮る
- (IBAction)rotateCameraPosition:(id)sender;//  カメラの前と後ろを入れ替える

//  操作メソッド

//  一通りセットアップしたら呼ぶコマンド
- (void)openCamera;

//  カメラを使うのをやめるとき
- (void)closeCamera;

//  フォーカスを合わせるとき
- (void)setFocusPoint:(CGPoint)pos; //view内の座標値で指定

//  フィルターを選択
- (void)setFilterWithName:(NSString*)name;

@end
