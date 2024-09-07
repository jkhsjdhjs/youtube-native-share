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

#import <UIKit/UIActivityViewController.h>

#import "YouTubeHeader/YTUIUtils.h"

#import "protobuf/objectivec/GPBDescriptor.h"
#import "protobuf/objectivec/GPBMessage.h"
#import "protobuf/objectivec/GPBUnknownField.h"
#import "protobuf/objectivec/GPBUnknownFieldSet.h"

@interface CustomGPBMessage : GPBMessage
+ (instancetype)deserializeFromString:(NSString*)string;
@end

@interface YTICommand : GPBMessage
@end

@interface ELMPBCommand : GPBMessage
@end

@interface ELMPBShowActionSheetCommand : GPBMessage
@property (nonatomic, strong, readwrite) ELMPBCommand *onAppear;
@property (nonatomic, assign, readwrite) BOOL hasOnAppear;
@end

@interface ELMContext : NSObject
@property (nonatomic, strong, readwrite) UIView *fromView;
@end

@interface ELMCommandContext : NSObject
@property (nonatomic, strong, readwrite) ELMContext *context;
@end

@interface YTIUpdateShareSheetCommand
@property (nonatomic, assign, readwrite) BOOL hasSerializedShareEntity;
@property (nonatomic, copy, readwrite) NSString *serializedShareEntity;
+ (GPBExtensionDescriptor*)updateShareSheetCommand;
@end

@interface YTIInnertubeCommandExtensionRoot
+ (GPBExtensionDescriptor*)innertubeCommand;
@end

@interface YTAccountScopedCommandResponderEvent
@property (nonatomic, strong, readwrite) YTICommand *command;
@property (nonatomic, strong, readwrite) UIView *fromView;
@end

@interface YTIShareEntityEndpoint
@property (nonatomic, assign, readwrite) BOOL hasSerializedShareEntity;
@property (nonatomic, copy, readwrite) NSString *serializedShareEntity;
+ (GPBExtensionDescriptor*)shareEntityEndpoint;
@end

typedef NS_ENUM(NSInteger, ShareEntityType) {
    ShareEntityFieldVideo = 1,
    ShareEntityFieldPlaylist = 2,
    ShareEntityFieldChannel = 3,
    ShareEntityFieldPost = 6,
    ShareEntityFieldClip = 8
};

static inline NSString* extractIdWithFormat(GPBUnknownFieldSet *fields, NSInteger fieldNumber, NSString *format) {
    if (![fields hasField:fieldNumber])
        return nil;
    GPBUnknownField *idField = [fields getField:fieldNumber];
    if ([idField.lengthDelimitedList count] != 1)
        return nil;
    NSString *id = [[NSString alloc] initWithData:[idField.lengthDelimitedList firstObject] encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:format, id];
}

static BOOL showNativeShareSheet(NSString *serializedShareEntity, UIView *sourceView) {
    GPBMessage *shareEntity = [%c(GPBMessage) deserializeFromString:serializedShareEntity];
    GPBUnknownFieldSet *fields = shareEntity.unknownFields;
    NSString *shareUrl;

    if ([fields hasField:ShareEntityFieldClip]) {
        GPBUnknownField *shareEntityClip = [fields getField:ShareEntityFieldClip];
        if ([shareEntityClip.lengthDelimitedList count] != 1)
            return NO;
        GPBMessage *clipMessage = [%c(GPBMessage) parseFromData:[shareEntityClip.lengthDelimitedList firstObject] error:nil];
        shareUrl = extractIdWithFormat(clipMessage.unknownFields, 1, @"https://youtube.com/clip/%@");
    }

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldChannel, @"https://youtube.com/channel/%@");

    if (!shareUrl) {
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPlaylist, @"%@");
        if (shareUrl) {
            if (![shareUrl hasPrefix:@"PL"] && ![shareUrl hasPrefix:@"FL"])
                shareUrl = [shareUrl stringByAppendingString:@"&playnext=1"];
            shareUrl = [@"https://youtube.com/playlist?list=" stringByAppendingString:shareUrl];
        }
    }

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldVideo, @"https://youtube.com/watch?v=%@");

    if (!shareUrl)
        shareUrl = extractIdWithFormat(fields, ShareEntityFieldPost, @"https://youtube.com/post/%@");

    if (!shareUrl)
        return NO;

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[shareUrl] applicationActivities:nil];
    activityViewController.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];

    UIViewController *topViewController = [%c(YTUIUtils) topViewControllerForPresenting];

    if (activityViewController.popoverPresentationController) {
        activityViewController.popoverPresentationController.sourceView = topViewController.view;
        activityViewController.popoverPresentationController.sourceRect = [sourceView convertRect:sourceView.bounds toView:topViewController.view];
    }

    [topViewController presentViewController:activityViewController animated:YES completion:nil];

    return YES;
}


/* -------------------- iPad Layout -------------------- */

%hook YTAccountScopedCommandResponderEvent
- (void)send {
    GPBExtensionDescriptor *shareEntityEndpointDescriptor = [%c(YTIShareEntityEndpoint) shareEntityEndpoint];
    if (![self.command hasExtension:shareEntityEndpointDescriptor])
        return %orig;
    YTIShareEntityEndpoint *shareEntityEndpoint = [self.command getExtension:shareEntityEndpointDescriptor];
    if (!shareEntityEndpoint.hasSerializedShareEntity)
        return %orig;
    if (!showNativeShareSheet(shareEntityEndpoint.serializedShareEntity, self.fromView))
        return %orig;
}
%end


/* ------------------- iPhone Layout ------------------- */

%hook ELMPBShowActionSheetCommand
- (void)executeWithCommandContext:(ELMCommandContext*)context handler:(id)_handler {
    if (!self.hasOnAppear)
        return %orig;
    GPBExtensionDescriptor *innertubeCommandDescriptor = [%c(YTIInnertubeCommandExtensionRoot) innertubeCommand];
    if (![self.onAppear hasExtension:innertubeCommandDescriptor])
        return %orig;
    YTICommand *innertubeCommand = [self.onAppear getExtension:innertubeCommandDescriptor];
    GPBExtensionDescriptor *updateShareSheetCommandDescriptor = [%c(YTIUpdateShareSheetCommand) updateShareSheetCommand];
    if(![innertubeCommand hasExtension:updateShareSheetCommandDescriptor])
        return %orig;
    YTIUpdateShareSheetCommand *updateShareSheetCommand = [innertubeCommand getExtension:updateShareSheetCommandDescriptor];
    if (!updateShareSheetCommand.hasSerializedShareEntity)
        return %orig;
    if (!showNativeShareSheet(updateShareSheetCommand.serializedShareEntity, context.context.fromView))
        return %orig;
}
%end
