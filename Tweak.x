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

    GPBMessage *shareEntity = [%c(GPBMessage) deserializeFromString:updateShareSheetCommand.serializedShareEntity];
    GPBUnknownFieldSet *fields = shareEntity.unknownFields;
    NSString *shareUrl;

    if ([fields hasField:ShareEntityFieldClip]) {
        GPBUnknownField *shareEntityClip = [fields getField:ShareEntityFieldClip];
        if ([shareEntityClip.lengthDelimitedList count] != 1)
            return %orig;
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
        return %orig;

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc]initWithActivityItems:@[shareUrl] applicationActivities:nil];
    [[%c(YTUIUtils) topViewControllerForPresenting] presentViewController:activityViewController animated:YES completion:^{}];
}
%end
