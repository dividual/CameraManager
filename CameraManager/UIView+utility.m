//
//  UIView+utility.m
//  Blink
//
//  Created by Shinya Matsuyama on 10/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "UIView+utility.h"

@implementation UIView (utility)

- (void)removeFromSuperviewAndAddToParentView:(UIView*)newParentView
{
    if(self.superview == newParentView)
        return;
    
    //  消えるの防止
    UIView *retainView = self;
    
    //  新しい位置
    CGRect newFrame = [newParentView convertRect:retainView.frame fromView:retainView.superview];
    
    //  現在の親から消す
    [retainView removeFromSuperview];
    
    //  位置を指定して新しい親に追加
    retainView.frame = newFrame;
    [newParentView addSubview:retainView];
}

@end
