/* YouTube Native Share - An iOS Tweak to replace YouTube's share sheet and remove source identifiers.
 * Copyright (C) 2024 YouTube Native Share Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <UIKit/UIKit.h>

#import "protobuf/objectivec/GPBDescriptor.h"
#import "protobuf/objectivec/GPBMessage.h"
#import "protobuf/objectivec/GPBUnknownField.h"
#import "protobuf/objectivec/GPBUnknownFields.h"

@interface YTUIUtils : NSObject
+ (UIViewController *)topViewControllerForPresenting;
@end

@interface CustomGPBMessage : GPBMessage
+ (instancetype)deserializeFromString:(NSString*)string;
@end

@interface YTICommand : GPBMessage
@end

@interface ELMContext : NSObject
@property (nonatomic, strong, readwrite) UIView *fromView;
@end

@interface ELMCommandContext : NSObject
@property (nonatomic, strong, readwrite) ELMContext *context;
@end

@interface ELMPBShowActionSheetCommand : GPBMessage
@end

@interface YTShareEntityEndpointCommandHandler : NSObject
@end

typedef NS_ENUM(NSInteger, ShareEntityType) {
    ShareEntityFieldVideo     = 1,
    ShareEntityFieldPlaylist  = 2,
    ShareEntityFieldChannel   = 3,
    ShareEntityFieldPost      = 6,
    ShareEntityFieldClip      = 8,
    ShareEntityFieldShortFlag = 10
};

static inline NSString *extractIdWithFormat(GPBUnknownFields *fields, NSInteger fieldNumber, NSString *format) {
    NSArray<GPBUnknownField *> *fieldArray = [fields fields:fieldNumber];
    if ([fieldArray count] != 1)
        return nil;
    NSString *value = [[NSString alloc] initWithData:[fieldArray firstObject].lengthDelimited encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:format, value];
}

static NSString *extractUrlFromFields(GPBUnknownFields *fields) {
    NSString *shareUrl;

    NSArray<GPBUnknownField *> *shareEntityClip = [fields fields:ShareEntityFieldClip];
    if ([shareEntityClip count] == 1) {
        GPBMessage *clipMessage = [%c(GPBMessage) parseFromData:[shareEntityClip firstObject].lengthDelimited error:nil];
        shareUrl = extractIdWithFormat([[%c(GPBUnknownFields) alloc] initFromMessage:clipMessage], 1, @"https://youtube.com/clip/%@");
    }

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldChannel, @"https://youtube.com/channel/%@");

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPost, @"https://youtube.com/post/%@");

    if (!shareUrl) {
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPlaylist, @"%@");
        if (shareUrl) {
            if (![shareUrl hasPrefix:@"PL"] && ![shareUrl hasPrefix:@"FL"])
                shareUrl = [shareUrl stringByAppendingString:@"&playnext=1"];
            shareUrl = [@"https://youtube.com/playlist?list=" stringByAppendingString:shareUrl];
        }
    }

    if (!shareUrl) {
        NSString *format = ([fields fields:ShareEntityFieldShortFlag].count > 0) ? @"https://youtube.com/shorts/%@" : @"https://youtube.com/watch?v=%@";
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldVideo, format);
    }

    return shareUrl;
}

static NSString *extractUrlFromDescription(NSString *desc) {
    NSRegularExpression *regex;
    NSTextCheckingResult *match;

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldChannel] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) return [NSString stringWithFormat:@"https://youtube.com/channel/%@", [desc substringWithRange:[match rangeAtIndex:1]]];

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldPost] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) return [NSString stringWithFormat:@"https://youtube.com/post/%@", [desc substringWithRange:[match rangeAtIndex:1]]];

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldPlaylist] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) {
        NSString *playlistId = [desc substringWithRange:[match rangeAtIndex:1]];
        if (![playlistId hasPrefix:@"PL"] && ![playlistId hasPrefix:@"FL"])
            playlistId = [playlistId stringByAppendingString:@"&playnext=1"];
        return [NSString stringWithFormat:@"https://youtube.com/playlist?list=%@", playlistId];
    }

    regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"", (long)ShareEntityFieldVideo] options:0 error:nil];
    match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (match) return [NSString stringWithFormat:@"https://youtube.com/watch?v=%@", [desc substringWithRange:[match rangeAtIndex:1]]];

    return nil;
}

static BOOL showNativeShareSheet(NSString *serializedShareEntity, UIView *sourceView) {
    GPBMessage *shareEntity = [%c(GPBMessage) deserializeFromString:serializedShareEntity];
    if (!shareEntity) return NO;

    NSString *shareUrl;
    GPBUnknownFields *fields = [[%c(GPBUnknownFields) alloc] initFromMessage:shareEntity];

    if (fields && [fields count] > 0)
        shareUrl = extractUrlFromFields(fields);
    else
        shareUrl = extractUrlFromDescription([shareEntity description]);

    if (!shareUrl) return NO;

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[shareUrl] applicationActivities:nil];
    activityViewController.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];

    UIViewController *topViewController = [%c(YTUIUtils) topViewControllerForPresenting];
    if (activityViewController.popoverPresentationController) {
        if (sourceView) {
            activityViewController.popoverPresentationController.sourceView = sourceView;
            activityViewController.popoverPresentationController.sourceRect = [sourceView convertRect:sourceView.bounds toView:topViewController.view];
        } else {
            activityViewController.popoverPresentationController.sourceView = topViewController.view;
            CGFloat w = [UIScreen mainScreen].bounds.size.width;
            CGFloat h = [UIScreen mainScreen].bounds.size.height;
            activityViewController.popoverPresentationController.sourceRect = CGRectMake(w / 2.0, h, 0, 0);
        }
    }
    [topViewController presentViewController:activityViewController animated:YES completion:nil];
    return YES;
}

%hook ELMPBShowActionSheetCommand
- (void)executeWithCommandContext:(ELMCommandContext *)context handler:(id)handler {
    NSString *desc = [self description];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"serialized_share_entity: \"([^\"]+)\"" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (!match) return %orig;

    NSString *serializedShareEntity = [desc substringWithRange:[match rangeAtIndex:1]];
    UIView *fromView;
    if ([context.context respondsToSelector:@selector(fromView)])
        fromView = context.context.fromView;

    if (!showNativeShareSheet(serializedShareEntity, fromView))
        return %orig;
}
%end

%hook YTShareEntityEndpointCommandHandler
- (void)executeWithCommand:(YTICommand *)command entry:(id)entry fromView:(UIView *)fromView sender:(id)sender {
    NSString *desc = [command description];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"serialized_share_entity: \"([^\"]+)\"" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    if (!match) return %orig;

    NSString *serializedShareEntity = [desc substringWithRange:[match rangeAtIndex:1]];
    if (!showNativeShareSheet(serializedShareEntity, fromView))
        return %orig;
}
%end
