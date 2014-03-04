//
//  ViewController.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 10/23/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GPUImage/GPUImage.h>
#import "PreviewView.h"

@interface ViewController : UIViewController

@property (weak, nonatomic) IBOutlet UILabel *filterNameLabel;
@property (weak, nonatomic) IBOutlet UISwitch *silentSwitch;
@property (weak, nonatomic) IBOutlet PreviewView *previewViewA;
@property (weak, nonatomic) IBOutlet UIButton *shutterButton;
@property (weak, nonatomic) IBOutlet UIButton *cameraRotateButton;
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UIImageView *focusView;
@property (weak, nonatomic) IBOutlet UIButton *chooseFilterButton;
@property (weak, nonatomic) IBOutlet UIButton *changeCameraModeButton;
@property (weak, nonatomic) IBOutlet UILabel *movieRecordedTime;
@property (weak, nonatomic) IBOutlet UILabel *movieRemainTime;

@end
