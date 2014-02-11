//
//  GPUImageFilter+ProcessSizeUtility.m
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 2/8/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import "GPUImageFilter+ProcessSizeUtility.h"

@implementation GPUImageFilter (ProcessSizeUtility)

- (CGSize)processingSize
{
    return inputTextureSize;
}

- (CGSize)forceProcessingAtSizeFixAspect:(CGSize)frameSize originalSize:(CGSize)originalSize scale:(CGFloat)scale
{
    CGFloat widthScale = frameSize.width/originalSize.width;
    CGFloat heightScale = frameSize.height/originalSize.height;
    CGFloat fixScale = MAX(widthScale, heightScale)*scale;
    
    if(fixScale>=1.0)
        return originalSize;
    
    CGSize fixSize = CGSizeMake(originalSize.width*fixScale, originalSize.height*fixScale);
    [self forceProcessingAtSize:fixSize];
    
    return fixSize;
}

@end
