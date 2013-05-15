//
//  MSNavigationPaneViewController.h
//  MSNavigationPaneViewController
//
//  Created by Eric Horacek on 9/4/12.
//  Copyright (c) 2012-2013 Monospace Ltd. All rights reserved.
//
//  This code is distributed under the terms and conditions of the MIT license.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "MSNavigationPaneViewController.h"
#import "PRTween.h"
#import <QuartzCore/QuartzCore.h>

//#define LAYOUT_DEBUG
#define WIDTH_ADJUSTMENT 20

// Sizes
const CGFloat MSNavigationPaneDefaultOpenStateRevealWidthLeft = 267.0;
const CGFloat MSNavigationPaneDefaultOpenStateRevealWidthTop = 200.0;
const CGFloat MSNavigationPaneOpenAnimationOvershot = 20.0;

// Appearance Type Constants
const CGFloat MSNavigationPaneAppearanceTypeZoomScaleFraction = 0.075;
const CGFloat MSNavigationPaneAppearanceTypeParallaxOffsetFraction = 0.35;

// Animation Durations
const CGFloat MSNavigationPaneAnimationDurationOpenToSide = 0.2;
const CGFloat MSNavigationPaneAnimationDurationClosedToSide = 0.5;
const CGFloat MSNavigationPaneAnimationDurationSideToClosed = 0.45;
const CGFloat MSNavigationPaneAnimationDurationOpenToClosed = 0.3;
const CGFloat MSNavigationPaneAnimationDurationClosedToOpen = 0.3;
const CGFloat MSNavigationPaneAnimationDurationSnap = 0.2;

// Velocity Thresholds
const CGFloat MSDraggableViewVelocityThreshold = 5.0;

typedef void (^ViewActionBlock)(UIView *view);

@interface UIView (ViewHierarchyAction)

- (void)superviewHierarchyAction:(ViewActionBlock)viewAction;

@end

@implementation UIView (ViewHierarchyAction)

- (void)superviewHierarchyAction:(ViewActionBlock)viewAction
{
    viewAction(self);
    [self.superview superviewHierarchyAction:viewAction];
}

@end

@interface MSNavigationPaneViewController () <UIGestureRecognizerDelegate> {
    
    UIViewController *_masterViewController;
    UIViewController *_rightMasterViewController;
    UIViewController *_paneViewController;
    MSNavigationPaneAppearanceType _appearanceType;
    MSNavigationPaneState _paneState;
    MSNavigationPaneOpenDirection _openDirection;
}

@property (nonatomic, assign) BOOL animatingPane;
@property (nonatomic, assign) BOOL animatingRotation;
@property (nonatomic, assign) CGPoint paneStartLocation;
@property (nonatomic, assign) CGPoint paneStartLocationInSuperview;
@property (nonatomic, assign) CGFloat paneVelocity;

@property (nonatomic, strong) UIPanGestureRecognizer *panePanGestureRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *paneTapGestureRecognizer;

- (void)initialize;
- (void)animatePaneToState:(MSNavigationPaneState)state duration:(CGFloat)duration bounce:(BOOL)bounce;
- (void)updateAppearance;
- (CGFloat)paneViewClosedFraction;
- (void)paneTapped:(UIPanGestureRecognizer *)gesureRecognizer;
- (void)panePanned:(UITapGestureRecognizer *)gesureRecognizer;

@end

@implementation MSNavigationPaneViewController

@dynamic masterViewController;
@dynamic rightMasterViewController;
@dynamic paneViewController;
@dynamic paneState;
@dynamic appearanceType;

#pragma mark - NSObject

- (void)dealloc
{
    [self.paneView removeObserver:self forKeyPath:@"frame"];
}

#pragma mark - UIViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
		[self initialize];
    }
    return self;
}

- (void)awakeFromNib
{
    [self initialize];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return self.masterViewController.supportedInterfaceOrientations;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // This prevents weird transform issues, set the transform to identity for the duration of the rotation, disables updates during rotation
    self.animatingRotation = YES;
    self.masterView.transform = CGAffineTransformIdentity;
    self.rightMasterView.transform = CGAffineTransformIdentity;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    // This prevents weird transform issues, set the transform to identity for the duration of the rotation, disables updates during rotation
    self.animatingRotation = NO;
    [self updateAppearance];
}

#pragma mark - MSNavigationPaneViewController

- (void)initialize
{
    self.view.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    [self.view setBackgroundColor:[UIColor whiteColor]];
    
    _paneState = MSNavigationPaneStateClosed;
    _appearanceType = MSNavigationPaneAppearanceTypeNone;
    _openDirection = MSNavigationPaneOpenDirectionHorizontal;
    _openStateRevealWidth = MSNavigationPaneDefaultOpenStateRevealWidthLeft;
    _paneDraggingEnabled = YES;
    _paneViewSlideOffAnimationEnabled = YES;
    
    _touchForwardingClasses = [NSMutableSet setWithObjects:UISlider.class, UISwitch.class, nil];
    
    _masterView = [[UIView alloc] initWithFrame:self.view.bounds];
    _masterView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    _masterView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_masterView];
    
    _paneView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.paneView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    self.paneView.backgroundColor = [UIColor clearColor];
    
    _rightMasterView = [[UIView alloc] initWithFrame:self.view.bounds];
    _rightMasterView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    _rightMasterView.backgroundColor = [UIColor whiteColor];
    [self.view insertSubview:_rightMasterView belowSubview:_masterView];
    
    // Ensure that the shadow extends beyond the edges of the screen
    self.paneView.layer.shadowPath = [[UIBezierPath bezierPathWithRect:CGRectInset(self.paneView.frame, -40.0, 0.0)] CGPath];
    self.paneView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.paneView.layer.shadowOpacity = 1.0;
    self.paneView.layer.shadowRadius = 10.0;
    self.paneView.layer.masksToBounds = NO;
    
    [self.view addSubview:self.paneView];
    
    [self.paneView addObserver:self forKeyPath:@"frame" options:NULL context:NULL];
    
    self.panePanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panePanned:)];
    self.panePanGestureRecognizer.minimumNumberOfTouches = 1;
    self.panePanGestureRecognizer.maximumNumberOfTouches = 1;
    self.panePanGestureRecognizer.delegate = self;
    [self.paneView addGestureRecognizer:self.panePanGestureRecognizer];
    
#if defined(LAYOUT_DEBUG)
    _masterView.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.1];
    _masterView.layer.borderColor = [[UIColor blueColor] CGColor];
    _masterView.layer.borderWidth = 2.0;
    
    self.paneView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.1];
    self.paneView.layer.borderColor = [[UIColor redColor] CGColor];
    self.paneView.layer.borderWidth = 2.0;
#endif
}

#pragma mark View Controller Accessors

- (UIViewController *)masterViewController
{
    return _masterViewController;
}

- (void)setMasterViewController:(UIViewController *)masterViewController
{
	if (self.masterViewController == nil) {
        
        masterViewController.view.frame = CGRectMake(0, 0, self.openStateRevealWidth + WIDTH_ADJUSTMENT, CGRectGetHeight(_masterView.bounds));
        CGRect frame = _masterView.frame;
        frame.size.width = masterViewController.view.frame.size.width;
        _masterView.frame = frame;
		_masterViewController = masterViewController;
		[self addChildViewController:self.masterViewController];
		[_masterView addSubview:self.masterViewController.view];
		[self.masterViewController didMoveToParentViewController:self];
        
	} else if (self.masterViewController != masterViewController) {
        
		masterViewController.view.frame = CGRectMake(0, 0, self.openStateRevealWidth + WIDTH_ADJUSTMENT, CGRectGetHeight(_masterView.bounds));
        CGRect frame = _masterView.frame;
        frame.size.width = masterViewController.view.frame.size.width;
        _masterView.frame = frame;
		[self.masterViewController willMoveToParentViewController:nil];
		[self addChildViewController:masterViewController];
        
        void(^transitionCompletion)(BOOL finished) = ^(BOOL finished) {
            [self.masterViewController removeFromParentViewController];
            [masterViewController didMoveToParentViewController:self];
            _masterViewController = masterViewController;
        };
        
		[self transitionFromViewController:self.masterViewController
						  toViewController:masterViewController
								  duration:0
								   options:UIViewAnimationOptionTransitionNone
								animations:nil
								completion:transitionCompletion];
	}
}

- (UIViewController *)rightMasterViewController
{
    return _rightMasterViewController;
}

- (void)setRightMasterViewController:(UIViewController *)rightMasterViewController
{
	if (self.rightMasterViewController == nil) {
        
        rightMasterViewController.view.frame = CGRectMake(0, 0, self.openStateRevealWidth + WIDTH_ADJUSTMENT, CGRectGetHeight(_rightMasterView.bounds));
        CGRect frame = _rightMasterView.frame;
        frame.size.width = rightMasterViewController.view.frame.size.width;
        frame.origin.x = CGRectGetWidth(self.view.frame) - frame.size.width;
        _rightMasterView.frame = frame;
		_rightMasterViewController = rightMasterViewController;
		[self addChildViewController:self.rightMasterViewController];
		[_rightMasterView addSubview:self.rightMasterViewController.view];
		[self.rightMasterViewController didMoveToParentViewController:self];
    } else if (self.rightMasterViewController != rightMasterViewController) {
		rightMasterViewController.view.frame = CGRectMake(0, 0, self.openStateRevealWidth + WIDTH_ADJUSTMENT, CGRectGetHeight(_rightMasterView.bounds));
        CGRect frame = _rightMasterView.frame;
        frame.size.width = rightMasterViewController.view.frame.size.width;
        frame.origin.x = CGRectGetWidth(self.view.frame) - frame.size.width;
        _rightMasterView.frame = frame;
		[self.rightMasterViewController willMoveToParentViewController:nil];
		[self addChildViewController:rightMasterViewController];
        
        void(^transitionCompletion)(BOOL finished) = ^(BOOL finished) {
            [self.rightMasterViewController removeFromParentViewController];
            [rightMasterViewController didMoveToParentViewController:self];
            _rightMasterViewController = rightMasterViewController;
            [_rightMasterView addSubview:self.rightMasterViewController.view];
        };
		[self transitionFromViewController:self.rightMasterViewController
						  toViewController:rightMasterViewController
								  duration:0
								   options:UIViewAnimationOptionTransitionNone
								animations:nil
								completion:transitionCompletion];
	}
}

- (UIViewController *)paneViewController
{
    return _paneViewController;
}

- (void)setPaneViewController:(UIViewController *)paneViewController
{
	if (self.paneViewController == nil) {
        
		paneViewController.view.frame = self.paneView.bounds;
		_paneViewController = paneViewController;
		[self addChildViewController:self.paneViewController];
		[self.paneView addSubview:self.paneViewController.view];
		[self.paneViewController didMoveToParentViewController:self];
        
	} else if (self.paneViewController != paneViewController) {
        
		paneViewController.view.frame = self.paneView.bounds;
		[self.paneViewController willMoveToParentViewController:nil];
		[self addChildViewController:paneViewController];
        
        void(^transitionCompletion)(BOOL finished) = ^(BOOL finished) {
            [self.paneViewController removeFromParentViewController];
            [paneViewController didMoveToParentViewController:self];
            _paneViewController = paneViewController;
        };
        
		[self transitionFromViewController:self.paneViewController
						  toViewController:paneViewController
								  duration:0
								   options:UIViewAnimationOptionTransitionNone
								animations:nil
								completion:transitionCompletion];
	}
}

- (void)setPaneViewController:(UIViewController *)paneViewController animated:(BOOL)animated completion:(void (^)(void))completion
{
    void(^internalCompletion)() = ^{
        self.view.userInteractionEnabled = YES;
        if ([self.delegate respondsToSelector:@selector(navigationPaneViewController:didAnimateToPane:)]) {
            [self.delegate navigationPaneViewController:self didAnimateToPane:paneViewController];
        }
        if (completion != nil) completion();
    };
    
    if (!animated || (paneViewController == self.paneViewController) || (self.paneViewController == nil)) {
        self.paneViewController = paneViewController;
        internalCompletion();
        return;
    }
    
    self.view.userInteractionEnabled = NO;
    
    void(^movePaneToSide)() = ^{
        CGRect paneViewFrame = self.paneView.frame;
        switch (self.openDirection) {
            case MSNavigationPaneOpenDirectionHorizontal:
                paneViewFrame.origin.x = CGRectGetWidth(self.view.frame) + MSNavigationPaneOpenAnimationOvershot;
                break;
            case MSNavigationPaneOpenDirectionTop:
                paneViewFrame.origin.y = CGRectGetHeight(self.view.frame) + MSNavigationPaneOpenAnimationOvershot;
                break;
        }
        self.paneView.frame = paneViewFrame;
    };
    
    void(^movePaneToClosed)() = ^{
        CGRect paneViewFrame = self.paneView.frame;
        paneViewFrame.origin = CGPointMake(0.0, 0.0);
        self.paneView.frame = paneViewFrame;
    };
    
    // If we're trying to animate to the currently visible pane view controller, just close
    if (paneViewController == self.paneViewController) {
        
        [UIView animateWithDuration:MSNavigationPaneAnimationDurationOpenToClosed
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:movePaneToClosed
                         completion:^(BOOL animationFinished) {
                             self.paneState = MSNavigationPaneStateClosed;
                             internalCompletion();
                         }];
    }
    // Otherwise, animate off to the right first, set the pane view controller, and then animate closed
    else {
        
        void(^newPaneCompletion)(BOOL finished) = ^(BOOL finished) {
            
            self.paneViewController = paneViewController;
            
            // Force redraw of the pane view (for smooth animation)
            [self.paneView setNeedsDisplay];
            [CATransaction flush];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Slide the pane back into view
                [UIView animateWithDuration:MSNavigationPaneAnimationDurationSideToClosed
                                      delay:0.0
                                    options:UIViewAnimationOptionCurveEaseInOut
                                 animations:movePaneToClosed
                                 completion:^(BOOL animationFinished) {
                                     if (animationFinished) {
                                         self.paneState = MSNavigationPaneStateClosed;
                                         internalCompletion();
                                     }
                                 }];
            });
        };
        
        CGFloat duration = 0.0;
        if (self.paneState == MSNavigationPaneStateOpen) {
            duration = MSNavigationPaneAnimationDurationOpenToSide;
        } else if (self.paneState == MSNavigationPaneStateClosed) {
            duration = MSNavigationPaneAnimationDurationClosedToSide;
        }
        
        if ([self.delegate respondsToSelector:@selector(navigationPaneViewController:willAnimateToPane:)]) {
            [self.delegate navigationPaneViewController:self willAnimateToPane:paneViewController];
        }
        
        if (self.paneViewSlideOffAnimationEnabled) {
            [UIView animateWithDuration:duration
                             animations:movePaneToSide
                             completion:newPaneCompletion];
        } else {
            newPaneCompletion(YES);
        }
    }
}

#pragma mark Pane View Animation

- (CGFloat)paneViewClosedFraction
{
    CGFloat fraction;
    switch (self.openDirection) {
        case MSNavigationPaneOpenDirectionHorizontal:
            fraction = ((self.openStateRevealWidth - self.paneView.frame.origin.x) / self.openStateRevealWidth);
            break;
        case MSNavigationPaneOpenDirectionTop:
            fraction = ((self.openStateRevealWidth - self.paneView.frame.origin.y) / self.openStateRevealWidth);
            break;
    }
    
    // Clip to 0.0 < fraction < 1.0
    fraction = (fraction < 0.0) ? 0.0 : fraction;
    fraction = (fraction > 1.0) ? 1.0 : fraction;
    return fraction;
}

- (CGFloat)leftViewClosedFraction {
    return [self paneViewClosedFraction];
}

- (CGFloat)rightViewClosedFraction {
    CGFloat fraction;
    switch (self.openDirection) {
        case MSNavigationPaneOpenDirectionHorizontal:
            fraction = (CGRectGetMaxX(self.paneView.frame) - CGRectGetMinX(self.rightMasterView.frame)) / CGRectGetWidth(self.rightMasterView.frame);
            break;
        case MSNavigationPaneOpenDirectionTop:
            fraction = ((self.openStateRevealWidth - self.paneView.frame.origin.y) / self.openStateRevealWidth);
            break;
    }
    
    // Clip to 0.0 < fraction < 1.0
    fraction = (fraction < 0.0) ? 0.0 : fraction;
    fraction = (fraction > 1.0) ? 1.0 : fraction;
    return fraction;
}

- (void)updateAppearance
{
    
    CGFloat leftClosedFraction = [self leftViewClosedFraction];
    CGFloat rightClosedFraction = [self rightViewClosedFraction];
    
    UIView *viewToTransform;
    CGFloat fraction = MIN(leftClosedFraction, rightClosedFraction);
    if (leftClosedFraction < rightClosedFraction) {
        viewToTransform = self.masterView;
    } else viewToTransform = self.rightMasterView;
    
    // This prevents weird transform issues
    if (self.animatingRotation) {
        return;
    }
    
    if (self.appearanceType == MSNavigationPaneAppearanceTypeZoom) {
        CGFloat scale = (1.0 - (fraction * MSNavigationPaneAppearanceTypeZoomScaleFraction));
        viewToTransform.transform = CGAffineTransformMakeScale(scale, scale);
    }
    else if (self.appearanceType == MSNavigationPaneAppearanceTypeParallax) {
        CGFloat translate = -((self.openStateRevealWidth * fraction) * MSNavigationPaneAppearanceTypeParallaxOffsetFraction);
        if (leftClosedFraction > rightClosedFraction) {
            translate = fabsf(translate);
        }
        CGAffineTransform transform;
        switch (self.openDirection) {
            case MSNavigationPaneOpenDirectionHorizontal:
                transform = CGAffineTransformMakeTranslation(translate, 0.0);
                break;
            case MSNavigationPaneOpenDirectionTop:
                transform = CGAffineTransformMakeTranslation(0.0, translate);
                break;
        }
        viewToTransform.transform = transform;
    }
    else if (self.appearanceType == MSNavigationPaneAppearanceTypeFade) {
        viewToTransform.alpha = (1.0 - fraction);
    }
    
    CGRect paneViewRect = (CGRect){CGPointZero, self.paneView.frame.size};
    switch (self.openDirection) {
        case MSNavigationPaneOpenDirectionHorizontal:
            self.paneView.layer.shadowPath = [[UIBezierPath bezierPathWithRect:CGRectInset(paneViewRect, 0.0, -40.0)] CGPath];
            break;
        case MSNavigationPaneOpenDirectionTop:
            self.paneView.layer.shadowPath = [[UIBezierPath bezierPathWithRect:CGRectInset(paneViewRect, -40.0, 0.0)] CGPath];
            break;
    }
}

- (void)animatePaneToState:(MSNavigationPaneState)state duration:(CGFloat)duration bounce:(BOOL)bounce
{
    
    // Notify delegate of pane state change
    if ([self.delegate respondsToSelector:@selector(navigationPaneViewController:willUpdateToPaneState:)]) {
        [self.delegate navigationPaneViewController:self willUpdateToPaneState:state];
    }
    
    CGFloat startPosition;
    switch (self.openDirection) {
        case MSNavigationPaneOpenDirectionHorizontal:
            startPosition = self.paneView.frame.origin.x;
            break;
        case MSNavigationPaneOpenDirectionTop:
            startPosition = self.paneView.frame.origin.y;
            break;
    }
    
    CGFloat endPosition;
    switch (state) {
        case MSNavigationPaneStateOpenLeft:{
            endPosition = self.openStateRevealWidth;
            break;
        } case MSNavigationPaneStateOpenRight:{
            endPosition = (-self.openStateRevealWidth - WIDTH_ADJUSTMENT);
            break;
        }
        case MSNavigationPaneStateOpen:
        case MSNavigationPaneStateClosed:{
            endPosition = 0.0;
            break;
        }
    }
    
    void(^tweenUpdate)(PRTweenPeriod *period) = ^(PRTweenPeriod *period) {
        CGRect newFrame = self.paneView.frame;
        switch (self.openDirection) {
            case MSNavigationPaneOpenDirectionHorizontal:
                newFrame.origin = CGPointMake(period.tweenedValue, 0.0);
                break;
            case MSNavigationPaneOpenDirectionTop:
                newFrame.origin = CGPointMake(0.0, period.tweenedValue);
                break;
        }
        self.paneView.frame = newFrame;
    };
    
    void(^tweenCompletion)() = ^() {
        self.animatingPane = NO;
        if (self.paneState != state) {
            self.paneState = state;
        }
    };
    
    self.animatingPane = YES;
    PRTweenPeriod *tweenPeriod = [PRTweenPeriod periodWithStartValue:startPosition endValue:endPosition duration:duration];
    PRTweenTimingFunction timingFunction = (bounce ? &PRTweenTimingFunctionBackOut : &PRTweenTimingFunctionQuadInOut);
    [[PRTween sharedInstance] addTweenPeriod:tweenPeriod updateBlock:tweenUpdate completionBlock:tweenCompletion timingFunction:timingFunction];
}

#pragma mark Appearance Type

- (void)setAppearanceType:(MSNavigationPaneAppearanceType)appearanceType
{
    // Reset scale transform if set to a new appearance type
    if (appearanceType != MSNavigationPaneAppearanceTypeZoom) {
        self.masterView.transform = CGAffineTransformIdentity;
        self.rightMasterView.transform = CGAffineTransformIdentity;
    }
    // Reset translate transform if set to a new appearance type
    if (appearanceType != MSNavigationPaneAppearanceTypeParallax) {
        self.masterView.transform = CGAffineTransformIdentity;
        self.rightMasterView.transform = CGAffineTransformIdentity;
    }
    if (appearanceType != MSNavigationPaneAppearanceTypeFade) {
        self.masterView.alpha = 1.0;
        self.rightMasterView.alpha = 1.0;
    }
    _appearanceType = appearanceType;
}

- (MSNavigationPaneAppearanceType)appearanceType
{
    return _appearanceType;
}

#pragma mark Pane State

- (MSNavigationPaneState)paneState
{
    return _paneState;
}

- (void)setPaneState:(MSNavigationPaneState)paneState
{
    [self setPaneState:paneState animated:NO completion:nil];
}

- (void)setPaneState:(MSNavigationPaneState)paneState animated:(BOOL)animated completion:(void (^)(void))completion
{
    void(^internalCompletion)() = ^ {
        _paneState = paneState;
        // Disable interation when pane is closed
        for (UIView *subview in self.paneView.subviews) {
            subview.userInteractionEnabled = (self.paneState == MSNavigationPaneStateClosed);
        }
        // Notify delegate of pane state change
        if ([self.delegate respondsToSelector:@selector(navigationPaneViewController:didUpdateToPaneState:)]) {
            [self.delegate navigationPaneViewController:self didUpdateToPaneState:self.paneState];
        }
        if (completion != nil) completion();
    };
    
    if (paneState == MSNavigationPaneStateClosed) {
        
        void(^animatePaneClosed)() = ^{
            CGRect paneViewFrame = self.paneView.frame;
            paneViewFrame.origin = CGPointMake(0.0, 0.0);
            self.paneView.frame = paneViewFrame;
        };
        
        void(^animatePaneClosedCompletion)(BOOL animationFinished) = ^(BOOL animationFinished) {
            internalCompletion();
            [self.paneView removeGestureRecognizer:self.paneTapGestureRecognizer];
        };
        
        if (animated) {
            [UIView animateWithDuration:MSNavigationPaneAnimationDurationClosedToOpen
                             animations:animatePaneClosed
                             completion:animatePaneClosedCompletion];
        } else {
            animatePaneClosed();
            animatePaneClosedCompletion(YES);
        }
        
    } else if (paneState == MSNavigationPaneStateOpenLeft || paneState == MSNavigationPaneStateOpenRight) {
        void(^animatePaneOpen)() = ^{
            CGRect paneViewFrame = self.paneView.frame;
            switch (self.openDirection) {
                case MSNavigationPaneOpenDirectionHorizontal:
                    switch (paneState) {
                        case MSNavigationPaneStateOpenLeft:{
                            paneViewFrame.origin.x = self.openStateRevealWidth;
                            break;
                        } case MSNavigationPaneStateOpenRight:{
                            paneViewFrame.origin.x = (-self.openStateRevealWidth - WIDTH_ADJUSTMENT);
                            break;
                        }
                        default:
                            break;
                    }
                    
                    break;
                case MSNavigationPaneOpenDirectionTop:
                    paneViewFrame.origin.y = self.openStateRevealWidth;
                    break;
            }
            self.paneView.frame = paneViewFrame;
        };
        
        void(^animatePaneOpenCompletion)(BOOL animationFinished) = ^(BOOL animationFinished) {
            internalCompletion();
            if (!self.paneTapGestureRecognizer) {
                self.paneTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(paneTapped:)];
                self.paneTapGestureRecognizer.numberOfTouchesRequired = 1;
                self.paneTapGestureRecognizer.numberOfTapsRequired = 1;
            }
            [self.paneView addGestureRecognizer:self.paneTapGestureRecognizer];
        };
        
        if (animated) {
            [self animatePaneToState:paneState duration:MSNavigationPaneAnimationDurationClosedToOpen bounce:NO];
            return;
            [UIView animateWithDuration:MSNavigationPaneAnimationDurationOpenToClosed
                             animations:animatePaneOpen
                             completion:animatePaneOpenCompletion];
        } else {
            animatePaneOpen();
            animatePaneOpenCompletion(YES);
        }
    }
}

#pragma mark Open Direction

- (MSNavigationPaneOpenDirection)openDirection
{
    return _openDirection;
}

- (void)setOpenDirection:(MSNavigationPaneOpenDirection)openDirection
{
    // Close the pane if it's currently open (before we update the direction)
    if (self.paneState == MSNavigationPaneStateOpen||self.paneState == MSNavigationPaneStateOpenRight||self.paneState == MSNavigationPaneStateOpenLeft) {
        self.paneState = MSNavigationPaneStateClosed;
    }
    
    _openDirection = openDirection;
    
    // Reset the master view's transform when the open direction is changed
    self.masterView.transform = CGAffineTransformIdentity;
    self.rightMasterView.transform = CGAffineTransformIdentity;
    [self updateAppearance];
}

#pragma mark - UIGestureRecognizer Callbacks

- (void)paneTapped:(UIPanGestureRecognizer *)gestureRecognizer
{
    [self animatePaneToState:MSNavigationPaneStateClosed duration:MSNavigationPaneAnimationDurationOpenToClosed bounce:NO];
}

- (void)panePanned:(UIPanGestureRecognizer *)gestureRecognizer
{
    if (!self.paneDraggingEnabled || self.animatingPane) {
        return;
    }
    
    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            self.paneStartLocation = [gestureRecognizer locationInView:self.paneView];
            self.paneVelocity = 0.0;
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint panLocationInPaneView = [gestureRecognizer locationInView:self.paneView];
            // Pane Sliding
            CGRect newFrame = self.paneView.frame;
            switch (self.openDirection) {
                case MSNavigationPaneOpenDirectionHorizontal: {
                    newFrame.origin.x += (panLocationInPaneView.x - self.paneStartLocation.x);
                    if (newFrame.origin.x > self.openStateRevealWidth) {
                        newFrame.origin.x = (self.openStateRevealWidth + nearbyintf(sqrtf((newFrame.origin.x - self.openStateRevealWidth) * 2.0)));
                    } else if (newFrame.origin.x < (-self.openStateRevealWidth - WIDTH_ADJUSTMENT)) {
                        newFrame.origin.x = ((-self.openStateRevealWidth - WIDTH_ADJUSTMENT) - nearbyintf(sqrtf((-newFrame.origin.x - self.openStateRevealWidth) * 2.0)));
                    }
                    self.paneView.frame = newFrame;
                    break;
                }
                case MSNavigationPaneOpenDirectionTop: {
                    newFrame.origin.y += (panLocationInPaneView.y - self.paneStartLocation.y);
                    if (newFrame.origin.y < 0.0) {
                        newFrame.origin.y = -nearbyintf(sqrtf(fabs(newFrame.origin.y) * 2.0));
                    } else if (newFrame.origin.y > self.openStateRevealWidth) {
                        newFrame.origin.y = (self.openStateRevealWidth + nearbyintf(sqrtf((newFrame.origin.y - self.openStateRevealWidth) * 2.0)));
                    }
                    self.paneView.frame = newFrame;
                    break;
                }
            }
            break;
        }
        case UIGestureRecognizerStateEnded: {
            CGFloat leftClosedFraction = [self leftViewClosedFraction];
            CGFloat rightClosedFraction = [self rightViewClosedFraction];
            if (leftClosedFraction < rightClosedFraction) {
                if (leftClosedFraction < 0.5) {
                    [self snapToState:MSNavigationPaneStateOpenLeft];
                } else [self snapToState:MSNavigationPaneStateClosed];
            } else {
                if (rightClosedFraction < 0.5) {
                    [self snapToState:MSNavigationPaneStateOpenRight];
                } else [self snapToState:MSNavigationPaneStateClosed];
            }
            break;
        }
        default:
            break;
    }
}

- (void)snapToState:(MSNavigationPaneState)state {
    [self animatePaneToState:state duration:MSNavigationPaneAnimationDurationSnap bounce:YES];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if (!self.paneDraggingEnabled) {
        return NO;
    }
    __block BOOL shouldReceiveTouch = YES;
    // Enumerate the view's superviews, checking for a touch-forwarding class
    [touch.view superviewHierarchyAction:^(UIView *view) {
        // Only enumerate while still receiving the touch
        if (shouldReceiveTouch) {
            // If the touch was in a touch forwarding view, don't handle the gesture
            [self.touchForwardingClasses enumerateObjectsUsingBlock:^(Class touchForwardingClass, BOOL *stop) {
                if ([view isKindOfClass:touchForwardingClass]) {
                    shouldReceiveTouch = NO;
                    *stop = YES;
                }
            }];
        }
    }];
    return shouldReceiveTouch;
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"frame"] && (object == self.paneView)) {
        CGRect newFrame = CGRectNull;
        if([object valueForKeyPath:keyPath] != [NSNull null]) {
            newFrame = [[object valueForKeyPath:keyPath] CGRectValue];
            [self updateAppearance];
        }
    }
}

@end
