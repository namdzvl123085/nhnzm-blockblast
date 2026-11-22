ARCHS = arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = NHNZMClient
NHNZMClient_FILES = NHNZMClient.m
NHNZMClient_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
NHNZMClient_CFLAGS = -fobjc-arc
NHNZMClient_LDFLAGS = -Wl,-install_name,@executable_path/Frameworks/NHNZMClient.dylib

include $(THEOS_MAKE_PATH)/library.mk
