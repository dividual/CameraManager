//
//  NSDate+stringUtility.m
//  CoreDataStudy
//
//  Created by Shinya Matsuyama on 12/22/13.
//  Copyright (c) 2013 Shinya Matsuyama. All rights reserved.
//

#import "NSDate+stringUtility.h"

@implementation NSDate (stringUtility)

- (NSString*)stringTimeStampFormat
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    
    return [formatter stringFromDate:self];
}

@end

