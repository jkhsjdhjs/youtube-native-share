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

#include <UIKit/UIActivityViewController.h>

#include "YouTubeHeader/YTUIUtils.h"

#include "protobuf/objectivec/GPBDescriptor.h"
#include "protobuf/objectivec/GPBMessage.h"
#include "protobuf/objectivec/GPBUnknownField.h"
#include "protobuf/objectivec/GPBUnknownFieldSet.h"

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

@interface YTIUpdateShareSheetCommand
@property (nonatomic, assign, readwrite) BOOL hasSerializedShareEntity;
@property (nonatomic, copy, readwrite) NSString *serializedShareEntity;
+ (GPBExtensionDescriptor*)updateShareSheetCommand;
@end

@interface YTIInnertubeCommandExtensionRoot
+ (GPBExtensionDescriptor*)innertubeCommand;
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

static BOOL showNativeShareSheet(NSString *serializedShareEntity) {
    GPBMessage *shareEntity = [%c(GPBMessage) deserializeFromString:serializedShareEntity];
    GPBUnknownFieldSet *fields = shareEntity.unknownFields;
    NSString *shareUrl;

    if ([fields hasField:ShareEntityFieldClip]) {
        GPBUnknownField *shareEntityClip = [fields getField:ShareEntityFieldClip];
        if ([shareEntityClip.lengthDelimitedList count] != 1)
            return FALSE;
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
        return FALSE;

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc]initWithActivityItems:@[shareUrl] applicationActivities:nil];
    [[%c(YTUIUtils) topViewControllerForPresenting] presentViewController:activityViewController animated:YES completion:^{}];
    return TRUE;
}


/* -------------------- iPad Layout -------------------- */

%hook YTShareRequestViewController
- (id)initWithService:(id)_service parentResponder:(id)_parentResponder {
    // disable the default share sheet behavior and force the app to call [YTAccountScopedCommandRouter handleCommand]
    return NULL;
}
%end

%hook YTAccountScopedCommandRouter
- (BOOL)handleCommand:(id)command entry:(id)_entry fromView:(id)_fromView sender:(id)_sender completionBlock:(id)_completionBlock {
    GPBExtensionDescriptor *shareEntityEndpointDescriptor = [%c(YTIShareEntityEndpoint) shareEntityEndpoint];
    if (![command hasExtension:shareEntityEndpointDescriptor])
        return %orig;
    YTIShareEntityEndpoint *shareEntityEndpoint = [command getExtension:shareEntityEndpointDescriptor];
    if(!shareEntityEndpoint.hasSerializedShareEntity)
        return %orig;
    if (!showNativeShareSheet(shareEntityEndpoint.serializedShareEntity))
        return %orig;
    return TRUE;
}
%end


/* ------------------- iPhone Layout ------------------- */

%hook ELMPBShowActionSheetCommand
- (void)executeWithCommandContext:(id)_context handler:(id)_handler {
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
    if (!showNativeShareSheet(updateShareSheetCommand.serializedShareEntity))
        return %orig;
}
%end
