#import "CPTGraphHostingView.h"

#import "CPTGraph.h"
#import "CPTPlotArea.h"
#import "CPTPlotAreaFrame.h"
#import "CPTPlotSpace.h"
#import "NSNumberExtensions.h"

///	@cond
@interface CPTGraphHostingView()

@property (nonatomic, readwrite, assign) __cpt_weak UIPinchGestureRecognizer *pinchGestureRecognizer;

-(void)graphNeedsRedraw:(NSNotification *)notification;

@end

///	@endcond

#pragma mark -

/**
 *	@brief A container view for displaying a CPTGraph.
 **/
@implementation CPTGraphHostingView

/**	@property hostedGraph
 *	@brief The CPTLayer hosted inside this view.
 **/
@synthesize hostedGraph;

/**	@property collapsesLayers
 *	@brief Whether view draws all graph layers into a single layer.
 *  Collapsing layers may improve performance in some cases.
 **/
@synthesize collapsesLayers;

/**	@property allowPinchScaling
 *	@brief Whether a pinch will trigger plot space scaling.
 *  Default is YES. This causes gesture recognizers to be added to identify pinches.
 **/
@synthesize allowPinchScaling;

///	@cond

/**	@internal
 *	@property pinchGestureRecognizer
 *	@brief The pinch gesture recognizer for this view.
 **/
@synthesize pinchGestureRecognizer;

///	@endcond

#pragma mark -
#pragma mark init/dealloc

///	@cond

+(Class)layerClass
{
    return [CALayer class];
}

-(void)commonInit
{
    hostedGraph     = nil;
    collapsesLayers = NO;

    self.backgroundColor = [UIColor clearColor];

    self.allowPinchScaling = YES;

    // This undoes the normal coordinate space inversion that UIViews apply to their layers
    self.layer.sublayerTransform = CATransform3DMakeScale(1.0, -1.0, 1.0);
}

-(id)initWithFrame:(CGRect)frame
{
    if ( (self = [super initWithFrame:frame]) ) {
        [self commonInit];
    }
    return self;
}

///	@endcond

// On iOS, the init method is not called when loading from a XIB
-(void)awakeFromNib
{
    [self commonInit];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark -
#pragma mark NSCoding methods

-(void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    [coder encodeBool:self.collapsesLayers forKey:@"CPTGraphHostingView.collapsesLayers"];
    [coder encodeObject:self.hostedGraph forKey:@"CPTGraphHostingView.hostedGraph"];
    [coder encodeBool:self.allowPinchScaling forKey:@"CPTGraphHostingView.allowPinchScaling"];

    // No need to archive these properties:
    // pinchGestureRecognizer
}

-(id)initWithCoder:(NSCoder *)coder
{
    if ( (self = [super initWithCoder:coder]) ) {
        collapsesLayers  = [coder decodeBoolForKey:@"CPTGraphHostingView.collapsesLayers"];
        hostedGraph      = nil;
        self.hostedGraph = [coder decodeObjectForKey:@"CPTGraphHostingView.hostedGraph"]; // setup layers

        allowPinchScaling      = NO;
        pinchGestureRecognizer = nil;

        self.allowPinchScaling = [coder decodeBoolForKey:@"CPTGraphHostingView.allowPinchScaling"]; // set gesture recognizer if needed
    }
    return self;
}

#pragma mark -
#pragma mark Touch handling

///	@cond

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    // Ignore pinch or other multitouch gestures
    if ( [[event allTouches] count] > 1 ) {
        return;
    }

    CGPoint pointOfTouch = [[[event touchesForView:self] anyObject] locationInView:self];
    if ( !collapsesLayers ) {
        pointOfTouch = [self.layer convertPoint:pointOfTouch toLayer:hostedGraph];
    }
    else {
        pointOfTouch.y = self.frame.size.height - pointOfTouch.y;
    }
    [hostedGraph pointingDeviceDownEvent:event atPoint:pointOfTouch];
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    CGPoint pointOfTouch = [[[event touchesForView:self] anyObject] locationInView:self];
    if ( !collapsesLayers ) {
        pointOfTouch = [self.layer convertPoint:pointOfTouch toLayer:hostedGraph];
    }
    else {
        pointOfTouch.y = self.frame.size.height - pointOfTouch.y;
    }
    [hostedGraph pointingDeviceDraggedEvent:event atPoint:pointOfTouch];
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint pointOfTouch = [[[event touchesForView:self] anyObject] locationInView:self];

    if ( !collapsesLayers ) {
        pointOfTouch = [self.layer convertPoint:pointOfTouch toLayer:hostedGraph];
    }
    else {
        pointOfTouch.y = self.frame.size.height - pointOfTouch.y;
    }
    [hostedGraph pointingDeviceUpEvent:event atPoint:pointOfTouch];
}

-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [hostedGraph pointingDeviceCancelledEvent:event];
}

///	@endcond

#pragma mark -
#pragma mark Gestures

///	@cond

-(void)setAllowPinchScaling:(BOOL)allowScaling
{
    if ( allowPinchScaling != allowScaling ) {
        allowPinchScaling = allowScaling;
        if ( allowPinchScaling ) {
            // Register for pinches
            UIPinchGestureRecognizer *gestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
            [self addGestureRecognizer:gestureRecognizer];
            self.pinchGestureRecognizer = gestureRecognizer;
        }
        else {
            UIPinchGestureRecognizer *pinchRecognizer = self.pinchGestureRecognizer;
            if ( pinchRecognizer ) {
                [self removeGestureRecognizer:pinchRecognizer];
                self.pinchGestureRecognizer = nil;
            }
        }
    }
}

-(void)handlePinchGesture:(UIPinchGestureRecognizer *)aPinchGestureRecognizer;
{
    CGPoint interactionPoint = [aPinchGestureRecognizer locationInView:self];
    CPTGraph *theHostedGraph = self.hostedGraph;
    
    theHostedGraph.frame = self.bounds;
    [theHostedGraph layoutIfNeeded];
    
    if ( self.collapsesLayers ) {
        interactionPoint.y = self.frame.size.height - interactionPoint.y;
    }
    else {
        interactionPoint = [self.layer convertPoint:interactionPoint toLayer:theHostedGraph];
    }
    
    CGPoint pointInPlotArea = [theHostedGraph convertPoint:interactionPoint toLayer:theHostedGraph.plotAreaFrame.plotArea];
    
    UIPinchGestureRecognizer *pinchRecognizer = self.pinchGestureRecognizer;
    
    CGFloat scale = pinchRecognizer.scale;
    
    for ( CPTPlotSpace *space in theHostedGraph.allPlotSpaces ) {
        if ( space.allowsUserInteraction ) {
            [space scaleBy:scale aboutPoint:pointInPlotArea];
        }
    }
    
    pinchRecognizer.scale = 1.0;
}

///	@endcond

#pragma mark -
#pragma mark Drawing

///	@cond

-(void)drawRect:(CGRect)rect
{
    if ( self.collapsesLayers ) {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextTranslateCTM(context, 0, self.bounds.size.height);
        CGContextScaleCTM(context, 1, -1);
        
        CPTGraph *theHostedGraph = self.hostedGraph;
        theHostedGraph.frame = self.bounds;
        [theHostedGraph layoutAndRenderInContext:context];
    }
}

-(void)graphNeedsRedraw:(NSNotification *)notification
{
    [self setNeedsDisplay];
}

///	@endcond

#pragma mark -
#pragma mark Accessors

///	@cond

-(void)setHostedGraph:(CPTGraph *)newLayer
{
    NSParameterAssert( (newLayer == nil) || [newLayer isKindOfClass:[CPTGraph class]] );

    if ( newLayer == hostedGraph ) {
        return;
    }

    if (hostedGraph) {
        [hostedGraph removeFromSuperlayer];
        hostedGraph.hostingView = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:CPTGraphNeedsRedrawNotification object:hostedGraph];
    }
    hostedGraph = newLayer;

    // Screen scaling
    UIScreen *screen = [UIScreen mainScreen];
    // scale property is available in iOS 4.0 and later
    if ( [screen respondsToSelector:@selector(scale)] ) {
        hostedGraph.contentsScale = screen.scale;
    }
    else {
        hostedGraph.contentsScale = 1.0;
    }
    hostedGraph.hostingView = self;

    if ( self.collapsesLayers ) {
        [self setNeedsDisplay];
        if ( hostedGraph ) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(graphNeedsRedraw:)
                                                         name:CPTGraphNeedsRedrawNotification
                                                       object:hostedGraph];
        }
    }
    else {
        if ( hostedGraph ) {
            hostedGraph.frame = self.layer.bounds;
            [self.layer addSublayer:hostedGraph];
        }
    }
}

-(void)setCollapsesLayers:(BOOL)collapse
{
    if ( collapse != collapsesLayers ) {
        collapsesLayers = collapse;
        
        CPTGraph *theHostedGraph = self.hostedGraph;
        
        if ( collapsesLayers ) {
            [theHostedGraph removeFromSuperlayer];
            [self setNeedsDisplay];
            
            if ( theHostedGraph ) {
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(graphNeedsRedraw:)
                                                             name:CPTGraphNeedsRedrawNotification
                                                           object:theHostedGraph];
            }
        }
        else {
            if ( theHostedGraph ) {
                [self.layer addSublayer:theHostedGraph];
                
                [[NSNotificationCenter defaultCenter] removeObserver:self
                                                                name:CPTGraphNeedsRedrawNotification
                                                              object:theHostedGraph];
            }
        }
    }
}

-(void)setFrame:(CGRect)newFrame
{
    [super setFrame:newFrame];
    
    CPTGraph *theHostedGraph = self.hostedGraph;
    [theHostedGraph setNeedsLayout];
    
    if ( self.collapsesLayers ) {
        [self setNeedsDisplay];
    }
    else {
        theHostedGraph.frame = self.bounds;
    }
}

-(void)setBounds:(CGRect)newBounds
{
    [super setBounds:newBounds];
    
    CPTGraph *theHostedGraph = self.hostedGraph;
    [theHostedGraph setNeedsLayout];
    
    if ( self.collapsesLayers ) {
        [self setNeedsDisplay];
    }
    else {
        theHostedGraph.frame = newBounds;
    }
}

///	@endcond

@end
