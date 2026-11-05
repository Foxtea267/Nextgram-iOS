#import "TGPhotoCropGridView.h"

@interface TGPhotoCropAreaView : UIControl

@property (nonatomic, copy) bool(^shouldBeginEditing)(void);
@property (nonatomic, copy) void(^didBeginEditing)(void);
@property (nonatomic, copy) void(^areaChanged)(void);
@property (nonatomic, copy) void(^didEndEditing)(void);

@property (nonatomic, assign) CGFloat aspectRatio;
@property (nonatomic, assign) bool lockAspectRatio;

@property (nonatomic, readonly) bool isTracking;
// MARK: NAGRAM
// The sides the control being dragged moves, none when nothing is dragged.
@property (nonatomic, readonly) UIRectEdge trackingEdges;

@property (nonatomic, assign) TGPhotoCropViewGridMode gridMode;

- (void)setGridMode:(TGPhotoCropViewGridMode)gridMode animated:(bool)animated;

@end

extern const CGSize TGPhotoCropCornerControlSize;
