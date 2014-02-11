//
//  UIView+utility.h
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIView (utility)

//  viewをsuperviewから消しつつ新しいviewに引っ越し
- (void)removeFromSuperviewAndAddToParentView:(UIView*)newParentView;

@end
