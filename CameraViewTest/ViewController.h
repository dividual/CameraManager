//
//  ViewController.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 10/23/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CameraView.h"

@interface ViewController : UIViewController <CameraViewDelegate>

@property (weak, nonatomic) IBOutlet CameraView *cameraView;
@property (weak, nonatomic) IBOutlet UILabel *filterNameLabel;

@end
