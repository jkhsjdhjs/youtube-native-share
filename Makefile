TARGET := iphone:clang:latest:8.0
INSTALL_TARGET_PROCESSES = YouTube


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouTubeNativeShare

YouTubeNativeShare_FILES = Tweak.x proto/ShareEntity.pbobjc.m
YouTubeNativeShare_CFLAGS = -fobjc-arc -Iprotobuf/objectivec

include $(THEOS_MAKE_PATH)/tweak.mk

# https://github.com/theos/theos/issues/481
SHELL = /usr/bin/bash

PROTO_FILES = share-entity.proto
PROTO_OUTPUT_DIR = proto

before-all::
	mkdir -p $(PROTO_OUTPUT_DIR)
	protoc --objc_out=$(PROTO_OUTPUT_DIR) $(PROTO_FILES)
