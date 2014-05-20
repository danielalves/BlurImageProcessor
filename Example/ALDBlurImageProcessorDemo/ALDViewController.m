//
//  ALDViewController.m
//  ALDBlurImageProcessorDemo
//
//  Created by Daniel L. Alves on 15/05/14.
//  Copyright (c) 2014 Daniel L. Alves. All rights reserved.
//

#import "ALDViewController.h"

// ald
#import "ALDBlurImageProcessor.h"

#pragma mark - Helper Functions

static float lerp( float percent, float x, float y ){ return x + ( percent * ( y - x ) ); };

#pragma mark - Defines

#define TEXT_FIELD_MIN_DY_FROM_KEYBOARD 10.0f

#pragma mark - Class Extension

@interface ALDViewController()< UITextFieldDelegate,
                                UIAlertViewDelegate,
                                UIActionSheetDelegate,
                                UIImagePickerControllerDelegate,
                                UINavigationControllerDelegate,
                                ALDBlurImageProcessorDelegate >
{
    BOOL fixingValues;
    ALDBlurImageProcessor *blurImageProcessor;
    
    UIAlertView *errorAlertView;
    __weak UITextField *currentTextField;
    UITapGestureRecognizer* keyboardDismissGestureRecognizer;
    
    __weak IBOutlet UIScrollView *scrollableContentView;
    
    __weak IBOutlet UIImageView *blurTargetImageView;
    __weak IBOutlet UISlider *blurSlider;
    
    __weak IBOutlet UITextField *blurRadiusMinValue;
    __weak IBOutlet UITextField *blurRadiusMaxValue;
    
    __weak IBOutlet UITextField *blurIterationsMinValue;
    __weak IBOutlet UITextField *blurIterationsMaxValue;
    
    __weak IBOutlet UISwitch *notificationMethodSwitch;
}
@end

#pragma mark - Implementation

@implementation ALDViewController

#pragma mark - Ctors & Dtor

-( void )dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: UIKeyboardWillShowNotification
                                                  object: nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: UIKeyboardWillHideNotification
                                                  object: nil];
    
    
    [self stopListeningToALDImageProcessorNotifications];
}

#pragma mark - View Lifecycle

-( void )viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onKeyboardWillShow: )
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onKeyboardWillHide: )
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
    
    blurImageProcessor = [[ALDBlurImageProcessor alloc] initWithImage: blurTargetImageView.image];
    
    keyboardDismissGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget: self
                                                                               action: @selector( dismissKeyboard )];
    keyboardDismissGestureRecognizer.cancelsTouchesInView = NO;
    keyboardDismissGestureRecognizer.enabled = NO;
    
    [scrollableContentView addGestureRecognizer: keyboardDismissGestureRecognizer];

    [self onNotificationMethodChanged: notificationMethodSwitch];
}

#pragma mark - Events

-( void )onTextFieldValueChanged:( UITextField * )textField
{
    if( fixingValues )
        return;
    
    fixingValues = YES;
    
    if( textField == blurRadiusMinValue || textField == blurRadiusMaxValue )
    {
        uint32_t minRadius = ( uint32_t )[blurRadiusMinValue.text integerValue];
        if( minRadius > 0 && ( minRadius & 1 ) == 0 )
            ++minRadius;
        
        uint32_t maxRadius = ( uint32_t )[blurRadiusMaxValue.text integerValue];
        if( maxRadius > 0 && ( maxRadius & 1 ) == 0 )
            ++maxRadius;
        
        if( maxRadius < minRadius )
            maxRadius = minRadius;
        
        blurRadiusMinValue.text = [NSString stringWithFormat: @"%d", minRadius];
        blurRadiusMaxValue.text = [NSString stringWithFormat: @"%d", maxRadius];
    }
    else
    {
        uint8_t minIterations = ( uint32_t )[blurIterationsMinValue.text integerValue];
        uint8_t maxIterations = ( uint32_t )[blurIterationsMaxValue.text integerValue];
        
        if( maxIterations < minIterations )
            maxIterations = minIterations;
        
        blurIterationsMinValue.text = [NSString stringWithFormat: @"%d", minIterations];
        blurIterationsMaxValue.text = [NSString stringWithFormat: @"%d", maxIterations];
    }
    
    fixingValues = NO;
    
    [self onSliderChanged];
}

-( IBAction )onSliderChanged
{
    [blurImageProcessor asyncBlurWithRadius: lerp( blurSlider.value, [blurRadiusMinValue.text integerValue], [blurRadiusMaxValue.text integerValue] )
                                 iterations: lerp( blurSlider.value, [blurIterationsMinValue.text integerValue], [blurIterationsMaxValue.text integerValue] )
                     cancelingLastOperation: NO];
}

-( IBAction )onNotificationMethodChanged:( UISwitch * )strategySwitch
{
    if( strategySwitch.on )
    {
        blurImageProcessor.delegate = nil;
        [self startListeningToALDImageProcessorNotifications];
    }
    else
    {
        [self stopListeningToALDImageProcessorNotifications];
        blurImageProcessor.delegate = self;
    }
}

-( IBAction )onImageTapped
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle: @"Change blurred image"
                                                             delegate: self
                                                    cancelButtonTitle: @"Cancel"
                                               destructiveButtonTitle: nil
                                                    otherButtonTitles: @"Take a photo", @"Pick from album", nil];
    [actionSheet showInView:self.view];
}

#pragma mark - ALDBlurImageProcessor Notifications

-( void )stopListeningToALDImageProcessorNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: ALDBlurImageProcessorImageReadyNotification
                                                  object: nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: ALDBlurImageProcessorImageProcessingErrorNotification
                                                  object: nil];
}

-( void )startListeningToALDImageProcessorNotifications
{
    [self stopListeningToALDImageProcessorNotifications];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onNewBlurredImage: )
                                                 name: ALDBlurImageProcessorImageReadyNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onBlurImageProcessorError: )
                                                 name: ALDBlurImageProcessorImageProcessingErrorNotification
                                               object: nil];
}

-( void )onNewBlurredImage:( NSNotification * )notification
{
    [self applyBlurredImage: notification.userInfo[ ALDBlurImageProcessorImageReadyNotificationBlurrredImageKey ]];
}

-( void )onBlurImageProcessorError:( NSNotification * )notification
{
    [self showBlurImageProcessorError: notification.userInfo[ ALDBlurImageProcessorImageProcessingErrorNotificationErrorKey ]];
}

#pragma mark - ALDBlurImageProcessorDelegate

-( void )onALDBlurImageProcessor:( ALDBlurImageProcessor * )blurImageProcessor newBlurrredImage:( UIImage * )image
{
    [self applyBlurredImage: image];
}

-( void )onALDBlurImageProcessor:( ALDBlurImageProcessor * )blurImageProcessor blurProcessingError:( NSNumber * )error
{
    [self showBlurImageProcessorError: error];
}

#pragma mark - Keyboard Management

-( void )dismissKeyboard
{
    [blurRadiusMinValue resignFirstResponder];
    [blurRadiusMaxValue resignFirstResponder];
    
    [blurIterationsMinValue resignFirstResponder];
    [blurIterationsMaxValue resignFirstResponder];
}

-( void )onKeyboardWillShow:( NSNotification * )notification
{
    CGRect keyboardFrame = [(( NSValue * )notification.userInfo[ UIKeyboardFrameEndUserInfoKey ]) CGRectValue];
    CGRect textFieldFrame = [currentTextField convertRect: currentTextField.bounds toView: currentTextField.window];
    
    CGRect intersection = CGRectIntersection( keyboardFrame, textFieldFrame );
    CGFloat dy = CGRectIsNull( intersection ) ? 0.0f :  ( textFieldFrame.origin.y - keyboardFrame.origin.y ) + textFieldFrame.size.height + TEXT_FIELD_MIN_DY_FROM_KEYBOARD;
    
    [self translateContentOriginY: -dy
                         duration: [(( NSNumber * )notification.userInfo[ UIKeyboardAnimationDurationUserInfoKey ]) doubleValue]
                   animationCurve: [(( NSNumber * )notification.userInfo[ UIKeyboardAnimationCurveUserInfoKey ]) integerValue]];
}

-( void )onKeyboardWillHide:( NSNotification * )notification
{
    [self translateContentOriginY: 0.0f
                         duration: [(( NSNumber * )notification.userInfo[ UIKeyboardAnimationDurationUserInfoKey ]) doubleValue]
                   animationCurve: [(( NSNumber * )notification.userInfo[ UIKeyboardAnimationCurveUserInfoKey ]) integerValue]];
}

-( void )translateContentOriginY:( CGFloat )dy duration:( NSTimeInterval )duration animationCurve:( UIViewAnimationCurve )animationCurve
{
    UIViewAnimationOptions animationCurveOption;
    switch( animationCurve )
    {
        case UIViewAnimationCurveEaseInOut:
            animationCurveOption = UIViewAnimationOptionCurveEaseInOut;
            break;
            
        case UIViewAnimationCurveEaseIn:
            animationCurveOption = UIViewAnimationOptionCurveEaseIn;
            break;
            
        case UIViewAnimationCurveEaseOut:
            animationCurveOption = UIViewAnimationOptionCurveEaseOut;
            break;
            
        case UIViewAnimationCurveLinear:
            animationCurveOption = UIViewAnimationOptionCurveLinear;
            break;
            
        default:
            animationCurveOption = UIViewAnimationOptionCurveEaseOut;
            break;
    }

    [UIView animateWithDuration: duration
                          delay: 0.0
                        options: UIViewAnimationOptionBeginFromCurrentState | animationCurveOption
                     animations: ^{
                         self.view.transform = CGAffineTransformMakeTranslation( 0.0f, dy );
                     }
                     completion: nil];
}

#pragma mark - UITextFieldDelegate

-( BOOL )textFieldShouldReturn:( UITextField * )textField
{
    [self dismissKeyboard];
    return YES;
}

-( void )textFieldDidBeginEditing:( UITextField * )textField
{
    currentTextField = textField;
    
    keyboardDismissGestureRecognizer.enabled = YES;
}

-( BOOL )textFieldShouldEndEditing:( UITextField * )textField
{
    currentTextField = nil;
    
    keyboardDismissGestureRecognizer.enabled = NO;
    return YES;
}

-( void )textFieldDidEndEditing:( UITextField * )textField
{
    [self onTextFieldValueChanged: textField];
}

#pragma mark - UIActionSheetDelegate

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if ( buttonIndex == actionSheet.cancelButtonIndex )
        return;
    
    if( buttonIndex == 0 )
    {
        if( [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera] )
        {
            [self showImagePickerForSourceType: UIImagePickerControllerSourceTypeCamera];
        }
        else
        {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Oops!"
                                                            message: @"Device has no camera"
                                                           delegate: nil
                                                  cancelButtonTitle: @"Ok"
                                                  otherButtonTitles: nil];
            [alert show];
        }
    }
    else
    {
        [self showImagePickerForSourceType: UIImagePickerControllerSourceTypePhotoLibrary];
    }
}

-( void )showImagePickerForSourceType:( UIImagePickerControllerSourceType )sourceType
{
    UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
    imagePickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
    imagePickerController.sourceType = sourceType;
    imagePickerController.delegate = self;
    
    if( sourceType == UIImagePickerControllerSourceTypeCamera )
    {
        imagePickerController.showsCameraControls = YES;
    }
    
    [self presentViewController: imagePickerController
                       animated: YES
                     completion: nil];
}

#pragma mark - UIImagePickerControllerDelegate

-( void )imagePickerController:( UIImagePickerController * )picker didFinishPickingMediaWithInfo:( NSDictionary * )info
{
    UIImage *image = [info valueForKey: UIImagePickerControllerOriginalImage];
    if( image )
    {
        blurTargetImageView.image = image;
        blurImageProcessor.imageToProcess = image;
        [self onSliderChanged];
    }
    
    [self dismissViewControllerAnimated: YES completion: nil];
}

#pragma mark - UIAlertViewDelegate

-( void )alertView:( UIAlertView * )alertView didDismissWithButtonIndex:( NSInteger )buttonIndex
{
    errorAlertView = nil;
}
#pragma mark - Helpers

-( void )applyBlurredImage:( UIImage * )image
{
    blurTargetImageView.image = image;
}

-( void )showBlurImageProcessorError:( NSNumber * )error
{
    if( errorAlertView )
        return;
    
    errorAlertView = [[UIAlertView alloc] initWithTitle: @"Blur Processing Error"
                                                message: [NSString stringWithFormat: @"Could not generate blurred image: vImage_Error %@", error]
                                               delegate: nil
                                      cancelButtonTitle: @"Ok"
                                      otherButtonTitles: nil];
    
    errorAlertView.delegate = self;
    [errorAlertView show];
}

@end
