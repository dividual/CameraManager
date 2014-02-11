//
//  GPUImageFilter+ProcessSizeUtility.h
//  CameraViewTest
//
//  Created by Shinya Matsuyama on 2/8/14.
//  Copyright (c) 2014 Shinya Matsuyama. All rights reserved.
//

#import "GPUImageFilter.h"

@interface GPUImageFilter (ProcessSizeUtility)

- (CGSize)processingSize;

- (CGSize)forceProcessingAtSizeFixAspect:(CGSize)frameSize originalSize:(CGSize)originalSize scale:(CGFloat)scale;

@end
