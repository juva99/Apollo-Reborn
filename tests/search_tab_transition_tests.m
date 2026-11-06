#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>

// UIKit doubles exercise the production shield's ownership and transition
// completion without needing Apollo's binary or an iOS Simulator.
@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic, readonly) CGRect bounds;
@property (nonatomic, strong) id window;
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, strong) NSMutableArray<UIView *> *subviews;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, copy) NSString *accessibilityIdentifier;
@property (nonatomic) BOOL accessibilityElementsHidden;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@implementation UIView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super init])) {
        _frame = frame;
        _alpha = 1;
        _subviews = [NSMutableArray array];
    }
    return self;
}
- (CGRect)bounds { return (CGRect){CGPointZero, self.frame.size}; }
- (void)addSubview:(UIView *)view {
    view.superview = self;
    view.window = self.window;
    [self.subviews addObject:view];
}
- (void)removeFromSuperview {
    [self.superview.subviews removeObjectIdenticalTo:self];
    self.superview = nil;
    self.window = nil;
}
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    for (UIView *ancestor = self; ancestor; ancestor = ancestor.superview)
        rect = CGRectOffset(rect, ancestor.frame.origin.x, ancestor.frame.origin.y);
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        rect = CGRectOffset(rect, -ancestor.frame.origin.x, -ancestor.frame.origin.y);
    return rect;
}
@end

typedef NS_ENUM(NSInteger, UIButtonType) { UIButtonTypeCustom };
typedef NS_OPTIONS(NSUInteger, UIControlEvents) { UIControlEventTouchDown = 1 };
@interface UIButton : UIView
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic) UIControlEvents events;
+ (instancetype)buttonWithType:(UIButtonType)type;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
- (void)press;
@end
@implementation UIButton
+ (instancetype)buttonWithType:(__unused UIButtonType)type {
    return [[self alloc] initWithFrame:CGRectZero];
}
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events {
    self.target = target;
    self.action = action;
    self.events = events;
}
- (void)press {
    void (*invoke)(id, SEL) = (void (*)(id, SEL))[self.target methodForSelector:self.action];
    invoke(self.target, self.action);
}
@end

@interface UITabBar : UIView @end
@implementation UITabBar @end
@interface UITabBarItem : NSObject
@property (nonatomic, strong) UIView *button;
@property (nonatomic, strong) UIView *fallbackButton;
@end
@implementation UITabBarItem @end

@protocol UIViewControllerTransitionCoordinatorContext
@property (nonatomic, readonly, getter=isCancelled) BOOL cancelled;
@end
@interface QATransition : NSObject <UIViewControllerTransitionCoordinatorContext>
@property (nonatomic, getter=isCancelled) BOOL cancelled;
@property (nonatomic) BOOL rejectsCompletion;
@property (nonatomic, copy) void (^completion)(id<UIViewControllerTransitionCoordinatorContext>);
- (BOOL)animateAlongsideTransition:(id)animation
                       completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion;
- (void)finish;
@end
@implementation QATransition
- (BOOL)animateAlongsideTransition:(__unused id)animation
                       completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion {
    if (self.rejectsCompletion) return NO;
    self.completion = completion;
    return YES;
}
- (void)finish {
    void (^completion)(id<UIViewControllerTransitionCoordinatorContext>) = self.completion;
    self.completion = nil;
    if (completion) completion(self);
}
@end

@interface UIViewController : NSObject
@property (nonatomic, strong) UIView *viewIfLoaded;
@property (nonatomic, strong) UIViewController *presentedViewController;
@property (nonatomic, strong) UITabBarItem *tabBarItem;
@property (nonatomic, strong) QATransition *transitionCoordinator;
@end
@implementation UIViewController @end
@interface UINavigationController : UIViewController
@property (nonatomic, copy) NSArray<UIViewController *> *viewControllers;
@property (nonatomic, readonly) UIViewController *topViewController;
@end
@implementation UINavigationController
- (UIViewController *)topViewController { return self.viewControllers.lastObject; }
@end
@interface UITabBarController : UIViewController
@property (nonatomic, strong) UITabBar *tabBar;
@property (nonatomic, strong) UIViewController *selectedViewController;
@end
@implementation UITabBarController @end
@interface UISearchBar : NSObject
@property (nonatomic) NSUInteger focusCount;
- (BOOL)becomeFirstResponder;
@end
@implementation UISearchBar
- (BOOL)becomeFirstResponder { self.focusCount++; return YES; }
@end
@interface QASearchController : UIViewController
@property (nonatomic, strong) UISearchBar *searchBar;
@end
@implementation QASearchController @end

static BOOL glass = YES;
static BOOL IsLiquidGlass(void) { return glass; }
static id ApolloSendObject(UITabBarItem *item, __unused SEL selector) { return item.button; }
static id ApolloObjectIvar(UITabBarItem *item, __unused const char *name) { return item.fallbackButton; }
static UISearchBar *ApolloSearchTabSearchBar(UIViewController *root) {
    return [(QASearchController *)root searchBar];
}

// PRODUCTION_SOURCE

static NSUInteger checks;
static void Require(BOOL condition, NSString *message) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static void DrainMainQueue(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!drained && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    Require(drained, @"queued focus completes");
}

@interface QAFixture : NSObject
@property (nonatomic, strong) UITabBarController *tabs;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) QASearchController *root;
@property (nonatomic, strong) QATransition *transition;
- (ApolloSearchTabTransitionShield *)install;
- (void)completeCancelled:(BOOL)cancelled;
@end
@implementation QAFixture
- (instancetype)init {
    if ((self = [super init])) {
        _root = [QASearchController new];
        _root.searchBar = [UISearchBar new];
        _root.viewIfLoaded = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
        _root.viewIfLoaded.window = [NSObject new];
        _nav = [UINavigationController new];
        _nav.viewControllers = @[_root, [UIViewController new]];
        _nav.tabBarItem = [UITabBarItem new];
        _tabs = [UITabBarController new];
        _tabs.selectedViewController = _nav;
        _tabs.viewIfLoaded = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
        _tabs.viewIfLoaded.window = _root.viewIfLoaded.window;
        _tabs.tabBar = [[UITabBar alloc] initWithFrame:CGRectMake(0, 700, 400, 80)];
        [_tabs.viewIfLoaded addSubview:_tabs.tabBar];
        _nav.tabBarItem.button = [[UIView alloc] initWithFrame:CGRectMake(240, 0, 80, 80)];
        [_tabs.tabBar addSubview:_nav.tabBarItem.button];
        _transition = [QATransition new];
    }
    return self;
}
- (ApolloSearchTabTransitionShield *)install {
    ApolloSearchTabTransitionShield *shield = ApolloSearchTabInstallTransitionShield(self.tabs, self.nav, self.root);
    self.nav.transitionCoordinator = self.transition;
    ApolloSearchTabObserveTransition(shield, self.nav);
    return shield;
}
- (void)completeCancelled:(BOOL)cancelled {
    self.transition.cancelled = cancelled;
    if (!cancelled) self.nav.viewControllers = @[self.root];
    self.nav.transitionCoordinator = nil;
    [self.transition finish];
    DrainMainQueue();
}
@end

int main(void) {
    @autoreleasepool {
        QAFixture *fixture = [QAFixture new];
        ApolloSearchTabTransitionShield *shield = [fixture install];
        Require(shield.superview == fixture.tabs.viewIfLoaded, @"the dock stays shielded while UIKit disables it");
        Require(CGRectEqualToRect(shield.frame, fixture.tabs.tabBar.frame), @"only the dock's footprint is shielded");
        UIButton *repeat = (UIButton *)shield.subviews.firstObject;
        Require(CGRectEqualToRect(repeat.frame, CGRectMake(240, 0, 80, 80)), @"Search's real button defines the repeat target");
        Require(repeat.events == UIControlEventTouchDown, @"the second touch is captured before it can select a list row");
        [repeat press];
        [repeat press];
        Require(fixture.root.searchBar.focusCount == 0, @"rapid repeats wait for the pop to settle");
        [fixture completeCancelled:NO];
        Require(shield.superview == nil && fixture.root.searchBar.focusCount == 1, @"rapid repeats focus Search exactly once after the pop");

        fixture = [QAFixture new];
        shield = [fixture install];
        [fixture completeCancelled:NO];
        Require(shield.superview == nil && fixture.root.searchBar.focusCount == 0, @"a single tap does not unexpectedly open the keyboard");

        fixture = [QAFixture new];
        shield = [fixture install];
        [shield repeatSearchTap];
        [fixture completeCancelled:YES];
        Require(shield.superview == nil && fixture.root.searchBar.focusCount == 0, @"a cancelled pop removes the shield without focusing a hidden root");

        fixture = [QAFixture new];
        shield = [fixture install];
        [shield repeatSearchTap];
        fixture.tabs.selectedViewController = [UIViewController new];
        [fixture completeCancelled:NO];
        Require(fixture.root.searchBar.focusCount == 0, @"switching tabs cancels the queued focus");

        fixture = [QAFixture new];
        shield = [fixture install];
        [shield repeatSearchTap];
        fixture.root.presentedViewController = [UIViewController new];
        [fixture completeCancelled:NO];
        Require(fixture.root.searchBar.focusCount == 0, @"a modal blocks queued keyboard focus");

        fixture = [QAFixture new];
        shield = [fixture install];
        [shield repeatSearchTap];
        fixture.root.viewIfLoaded.window = nil;
        [fixture completeCancelled:NO];
        Require(fixture.root.searchBar.focusCount == 0, @"a disappearing root cannot steal focus");

        fixture = [QAFixture new];
        shield = ApolloSearchTabInstallTransitionShield(fixture.tabs, fixture.nav, fixture.root);
        ApolloSearchTabObserveTransition(shield, fixture.nav);
        Require(shield.superview == nil, @"a synchronous or rejected pop never leaves an input shield behind");

        fixture = [QAFixture new];
        fixture.transition.rejectsCompletion = YES;
        shield = [fixture install];
        Require(shield.superview == nil, @"a rejected transition observer releases the shield");

        fixture = [QAFixture new];
        fixture.nav.tabBarItem.fallbackButton = fixture.nav.tabBarItem.button;
        fixture.nav.tabBarItem.button = nil;
        shield = [fixture install];
        Require(shield.subviews.count == 1, @"the legacy tab button lookup retains Search's repeat target");
        [fixture completeCancelled:NO];

        fixture = [QAFixture new];
        glass = NO;
        Require(ApolloSearchTabInstallTransitionShield(fixture.tabs, fixture.nav, fixture.root) == nil, @"standard builds retain native behavior");
        glass = YES;
        fixture.tabs.tabBar.hidden = YES;
        Require(ApolloSearchTabInstallTransitionShield(fixture.tabs, fixture.nav, fixture.root) == nil, @"a hidden dock never gets a shield");
        fixture.tabs.tabBar.hidden = NO;
        fixture.nav.viewControllers = @[fixture.root];
        Require(ApolloSearchTabInstallTransitionShield(fixture.tabs, fixture.nav, fixture.root) == nil, @"Search-root scrolling and focus keep the existing reselect path");
    }
    printf("search tab transition: %lu checks passed\n", (unsigned long)checks);
    return 0;
}
