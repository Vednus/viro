
//
//  VRTSceneNavigator.m
//  React
//
//  Created by Vik Advani on 3/11/16.
//  Copyright © 2016 Viro Media. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import <ViroKit/ViroKit.h>
#import <React/RCTAssert.h>
#import <React/RCTLog.h>
#import "VRTSceneNavigator.h"
#import "VRTScene.h"
#import "VRTNotifications.h"
#import <React/RCTRootView.h>
#import <React/RCTUtils.h>
#import "VRTPerfMonitor.h"
#import "VRTMaterialManager.h"
#import "VRTMaterialVideo.h"

/**
 VRTSceneNavigator manages the various scenes that a Viro App can navigate between.
 **/

@implementation VRTSceneNavigator {
    id <VROView> _vroView;
}

- (instancetype)initWithBridge:(RCTBridge *)bridge {
    self = [super initWithBridge:bridge];
    if (self) {
        
    }
    return self;
}

/*
 We defer creating the VR view until either the Scene is added or
 VR mode is set. This way we're able to disable VR mode prior to creating
 the view, which is important because if VR mode is enabled we force
 landscape mode, and if VR mode is not we do not.
 
 Ideally we'd be able to set VR mode after the fact, but GVR bugs prevent
 this (the double-viewport issue). Return YES if we created a new _vroView, NO if
 one already exists and the method was a no-op.
 */

-(void)setCurrentSceneIndex:(NSInteger)index {
    int currentViewsLength = (int)[_currentViews count];
    _currentSceneIndex = index;
    
    if (_currentSceneIndex < 0 || _currentSceneIndex > (currentViewsLength - 1)){
        // setCurrentSceneTag may be set before insertReactSubView class.
        // In this case, just return.
        return;
    }
    
    VRTScene *sceneView = [_currentViews objectAtIndex:index];
    [self setSceneView:sceneView];
}

- (void)removeReactSubview:(UIView *)subview {
    VRTScene *sceneView = (VRTScene *)subview;
    [self.currentViews removeObject:sceneView];
    [super removeReactSubview:subview];
}

- (NSArray *)reactSubviews {
    return self.currentViews;
}

- (UIView *)reactSuperview{
    return nil;
}

#pragma mark - VRORenderDelegate methods

- (void)setupRendererWithDriver:(std::shared_ptr<VRODriver>)driver {
    
}

- (void)userDidRequestExitVR {
    // Notify javascript listeners (for ReactNativeJs to ViroReactJs cases)
    if (self.onExitViro != nil) {
        self.onExitViro(nil);
    }
    
    // Notify Native listeners (for NativeApp to ViroReactJs cases)
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:kVRTOnExitViro object:nil]];
}

- (void)setSceneView:(VRTScene *)sceneView {
    if (_currentScene == sceneView) {
        return;
    }
    
    if (_currentScene == nil) {
        [_vroView setSceneController:[sceneView sceneController]];
    } else {
        [_vroView setSceneController:[sceneView sceneController] duration:1 timingFunction:VROTimingFunctionType::EaseIn];
    }
    _currentScene = sceneView;
}

// recursively traverse down the scene tree to apply materials. This is invoked after reloaded materials from initVRView() to ensure components are applying the latest reloaded materials.
- (void)applyMaterialsToSceneChildren:(VRTView *)view {
    NSArray *children = [view reactSubviews];
    if (children != nil && children.count > 0) {
        for (VRTView *childView in children) {
            if ([childView respondsToSelector:@selector(applyMaterials)]) {
                if ([childView isKindOfClass:[VRTNode class]]) {
                    VRTNode *node = (VRTNode *)childView;
                    [node applyMaterials];
                }
            }
            [self applyMaterialsToSceneChildren:childView];
        }
    }
}
/*
 Unproject the given screen coordinates into world coordinates. The given screen coordinate vector must
 contain a Z element in the range [0,1], where 0 is the near clipping plane and 1 the far clipping plane.
 */
- (VROVector3f) unprojectPoint:(VROVector3f)point {
    if (_vroView == nil || _vroView.renderer == nil) {
        RCTLogError(@"Unable to unproject. Renderer not intialized");
    }

    VROVector3f unprojectedPoint = [_vroView unprojectPoint:point];
    return unprojectedPoint;
}

// Project the given world coordinates into screen coordinates.
- (VROVector3f) projectPoint:(VROVector3f)point {
    if (_vroView == nil || _vroView.renderer == nil) {
        RCTLogError(@"Unable to unproject. Renderer not intialized");
    }

    VROVector3f projectedPoint = [_vroView projectPoint:point];
    return projectedPoint;
}


// Return the RCTRootView, if any, descending from the given controller
-(RCTRootView *) findRCTRootView:(UIViewController *)controller {
    if ([controller.view isKindOfClass:[RCTRootView class]]) {
        return (RCTRootView *)controller.view;
    }
    for (UIView *view in controller.view.subviews) {
        if([view isKindOfClass:[RCTRootView class]]) {
            return (RCTRootView *)view;
        }
    }

    if (controller.childViewControllers == nil) {
        return nil;
    }
    
    for (UIViewController *controllerChild in controller.childViewControllers) {
        if (controllerChild.view != nil) {
            if ([controllerChild.view isKindOfClass:[RCTRootView class]]) {
                return (RCTRootView *)controllerChild.view;
            }
            for (UIView *view in controllerChild.view.subviews) {
                if ([view isKindOfClass:[RCTRootView class]]) {
                    return (RCTRootView *)view;
                }
            }
        }

        RCTRootView *potentialRootView = [self findRCTRootView:controllerChild];
        if (potentialRootView != nil) {
            return potentialRootView;
        }
    }
    return nil;
}

#pragma mark RCTInvalidating methods

- (void)invalidate {
    //NOTE: DO NOT NULL OUT _currentViews here, that will cause a memory leak and prevent child views from
    //being released.
    //_currentViews = nil;
    _currentScene = nil;
    _vroView = nil;
    _childViews = nil;
}

@end
