//
//  ALDBlurImageProcessorTests.m
//  ALDBlurImageProcessorTests
//
//  Created by Daniel L. Alves on 15/05/14.
//  Copyright (c) 2014 Daniel L. Alves. All rights reserved.
//

#import <XCTest/XCTest.h>

// ios
#import <Accelerate/Accelerate.h>

// ald
#import "ALDBlurImageProcessor.h"

// pods
#import <Redefine/ALDRedefinition.h>

// Hack needed to force blur processing errors
@interface ALDBlurImageProcessor( RevealInternalMethods )

-( UIImage * )blurImage:( UIImage * )originalImage
             withRadius:( uint32_t )radius
             iterations:( uint8_t )iterations
              errorCode:( out NSNumber ** )errorCode;

@end

#pragma mark - Globals

static ALDRedefinition *makeBlurFailRedefinition = nil;

static NSOperationQueue *helperOperationQueue = nil;

static UIImage *testImage = nil;
static UIImage *testRetinaImage = nil;

static void *originalTestImagePixelData = NULL;
static void *originalTestRetinaImagePixelData = NULL;

#pragma mark - Interface

@interface ALDBlurImageProcessorTests : XCTestCase< ALDBlurImageProcessorDelegate >
{
    BOOL successBlockCalled;
    BOOL successDelegateCalled;
    BOOL successNotificationSent;
    
    BOOL errorBlockCalled;
    BOOL errorDelegateCalled;
    BOOL errorNotificationSent;
}
@end

#pragma mark - Implementation

@implementation ALDBlurImageProcessorTests

+( void )setUp
{
    helperOperationQueue = [[NSOperationQueue alloc] init];
    [helperOperationQueue setMaxConcurrentOperationCount: NSOperationQueueDefaultMaxConcurrentOperationCount];
    [helperOperationQueue setName: @"Helper Operation Queue"];

    [self createTestImages];
    
    makeBlurFailRedefinition = [ALDRedefinition redefineClassInstances: ALDBlurImageProcessor.class
                                                              selector: @selector( blurImage:withRadius:iterations:errorCode: )
                                                    withImplementation: ^id( id object, ... ) {

                                                        va_list argumentList;
                                                        va_start( argumentList, object );
                                                        
                                                        // Ignores originalImage, radius and iterations
                                                        UIImage* originalImage = va_arg( argumentList, UIImage* );
                                                        uint32_t radius = va_arg( argumentList, uint32_t );
                                                        
                                                        // uint8_t are promoted to int..
                                                        uint8_t iterations = va_arg( argumentList, int );
                                                        
                                                        // Force an error
                                                        NSNumber * __autoreleasing *errorCode = va_arg( argumentList, NSNumber* __autoreleasing * );
                                                        if( errorCode )
                                                            *errorCode = @( kvImageInvalidImageFormat );
                                                        
                                                        va_end( argumentList );
                                                        
                                                        // Returns no image
                                                        return nil;
                                                    }];
    [makeBlurFailRedefinition stopUsingRedefinition];
}

+( void )createTestImages
{
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef testImageContext = CGBitmapContextCreate( NULL, 64, 64, 8, 0, colorSpace, ( CGBitmapInfo )kCGImageAlphaPremultipliedLast );
    
    CGFloat gradientColorComps[] = { 0.0f, 0.0f, 0.0f, 1.0f,
                                     0.0f, 0.0f, 1.0f, 1.0f };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents( colorSpace,
                                                                  gradientColorComps,
                                                                  NULL,
                                                                  2 );
    
    CGColorSpaceRelease( colorSpace );
    
    CGContextDrawLinearGradient( testImageContext,
                                 gradient,
                                 CGPointMake( 32.0f, 0.0f ),
                                 CGPointMake( 32.0f, 64.0f ),
                                 0 );
    
    CGGradientRelease( gradient );
    
    CGImageRef testImageRef = CGBitmapContextCreateImage( testImageContext );
    CGContextRelease( testImageContext );
    
    testImage = [UIImage imageWithCGImage: testImageRef scale: 1.0f orientation: UIImageOrientationUp];
    testRetinaImage = [UIImage imageWithCGImage: testImageRef scale: 2.0f orientation: UIImageOrientationUp];
    
    CGImageRelease( testImageRef );
    
    originalTestImagePixelData = [self pixelDataFromImage: testImage pixelBufferSize: NULL];
    originalTestRetinaImagePixelData = [self pixelDataFromImage: testRetinaImage pixelBufferSize: NULL];
}

+( void )tearDown
{
    makeBlurFailRedefinition = nil;
    
    helperOperationQueue = nil;
    
    testImage = nil;
    testRetinaImage = nil;
    
    if( originalTestImagePixelData )
        free( originalTestImagePixelData );
    
    if( originalTestRetinaImagePixelData )
        free( originalTestRetinaImagePixelData );
}

-( void )setUp
{
    successBlockCalled = NO;
    successDelegateCalled = NO;
    successNotificationSent = NO;
    
    errorBlockCalled = NO;
    errorDelegateCalled = NO;
    errorNotificationSent = NO;
}

-( void )tearDown
{
    [self stopListeningToNotifications];
    [makeBlurFailRedefinition stopUsingRedefinition];
}

-( void )test_allows_empty_initialization
{
    XCTAssertNoThrow( [ALDBlurImageProcessor new] );
}

-( void )test_allows_target_image_switching_after_empty_initialization
{
    ALDBlurImageProcessor *blurProcessor = [ALDBlurImageProcessor new];
    
    XCTAssertNoThrow( blurProcessor.imageToProcess = testImage );
}

-( void )test_allows_target_image_switching_after_full_initialization
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    
    XCTAssertNoThrow( blurProcessor.imageToProcess = testRetinaImage );
}

-( void )test_non_zero_even_radius_do_not_generate_errors_and_return_blurred_images
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];

    UIImage *blurredImage = [blurProcessor syncBlurWithRadius: 2 iterations: 1 errorCode: nil];
    
    XCTAssertNotEqual( blurProcessor.imageToProcess, blurredImage );
    
    int ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurProcessor.imageToProcess
                                               toPixelDataFromImage: blurredImage];
    
    XCTAssertNotEqual( ret, 0 );
    
    ALDBlurImageProcessor *retinaBlurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testRetinaImage];
    
    blurredImage = [retinaBlurProcessor syncBlurWithRadius: 2 iterations: 1 errorCode: nil];
    
    XCTAssertNotEqual( retinaBlurProcessor.imageToProcess, blurredImage );
    
    ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: retinaBlurProcessor.imageToProcess
                                           toPixelDataFromImage: blurredImage];
    
    XCTAssertNotEqual( ret, 0 );
}

-( void )test_non_zero_radius_non_zero_iterations_generates_new_blurred_image
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testRetinaImage];

    UIImage *blurredImage = [blurProcessor syncBlurWithRadius: 1 iterations: 1 errorCode: nil];
    
    XCTAssertNotEqual( blurProcessor.imageToProcess, blurredImage );
    
    int ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurProcessor.imageToProcess
                                               toPixelDataFromImage: blurredImage];
    
    XCTAssertNotEqual( ret, 0 );
    
    blurredImage = [blurProcessor syncBlurWithRadius: 13 iterations: 5 errorCode: nil];
    
    XCTAssertNotEqual( blurProcessor.imageToProcess, blurredImage );
    
    ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurProcessor.imageToProcess
                                           toPixelDataFromImage: blurredImage];
    
    XCTAssertNotEqual( ret, 0 );
}

-( void )test_zero_radius_non_zero_iterations_returns_original_image
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testRetinaImage];
    
    UIImage *blurredImage = [blurProcessor syncBlurWithRadius: 0 iterations: 1 errorCode: nil];
    
    XCTAssertEqual( blurProcessor.imageToProcess, blurredImage );

    int ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurredImage
                                                        toPixelData: originalTestRetinaImagePixelData];
    
    XCTAssertEqual( ret, 0 );
    
    blurredImage = [blurProcessor syncBlurWithRadius: 0 iterations: 3 errorCode: nil];
    
    XCTAssertEqual( blurProcessor.imageToProcess, blurredImage );

    ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurredImage
                                                    toPixelData: originalTestRetinaImagePixelData];
    
    XCTAssertEqual( ret, 0 );
}

-( void )test_non_zero_radius_zero_iterations_returns_original_image
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testRetinaImage];
    
    UIImage *blurredImage = [blurProcessor syncBlurWithRadius: 1 iterations: 0 errorCode: nil];
    
    XCTAssertEqual( blurProcessor.imageToProcess, blurredImage );
    
    int ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurredImage
                                                        toPixelData: originalTestRetinaImagePixelData];
    
    XCTAssertEqual( ret, 0 );
    
    blurredImage = [blurProcessor syncBlurWithRadius: 7 iterations: 0 errorCode: nil];
    
    XCTAssertEqual( blurProcessor.imageToProcess, blurredImage );
    
    ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurredImage
                                                    toPixelData: originalTestRetinaImagePixelData];
    
    XCTAssertEqual( ret, 0 );
}

-( void )test_zero_radius_zero_iterations_returns_original_image
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    
    UIImage *blurredImage = [blurProcessor syncBlurWithRadius: 0 iterations: 0 errorCode: nil];
    
    XCTAssertEqual( blurProcessor.imageToProcess, blurredImage );
    
    int ret = [ALDBlurImageProcessorTests comparePixelDataFromImage: blurredImage
                                                        toPixelData: originalTestImagePixelData];
    
    XCTAssertEqual( ret, 0 );
}

-( void )test_throws_NSInvalidArgumentException_on_sync_blur_with_no_image_to_process
{
    ALDBlurImageProcessor *blurProcessor = [ALDBlurImageProcessor new];
  
    XCTAssertThrowsSpecificNamed( [blurProcessor syncBlurWithRadius: 9 iterations: 2 errorCode: nil], NSException, NSInvalidArgumentException );
    
    blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    blurProcessor.imageToProcess = nil;
    
    XCTAssertThrowsSpecificNamed( [blurProcessor syncBlurWithRadius: 1 iterations: 1 errorCode: nil], NSException, NSInvalidArgumentException );
}

-( void )test_throws_NSInvalidArgumentException_on_async_blur_with_no_image_to_process
{
    ALDBlurImageProcessor *blurProcessor = [ALDBlurImageProcessor new];
    
    XCTAssertThrowsSpecificNamed( [blurProcessor asyncBlurWithRadius: 9 iterations: 2], NSException, NSInvalidArgumentException );
    
    blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    blurProcessor.imageToProcess = nil;
    
    XCTAssertThrowsSpecificNamed( [blurProcessor asyncBlurWithRadius: 1 iterations: 1], NSException, NSInvalidArgumentException );
    
    blurProcessor = [ALDBlurImageProcessor new];
    
    XCTAssertThrowsSpecificNamed( [blurProcessor asyncBlurWithRadius: 9 iterations: 2 cancelingLastOperation: YES], NSException, NSInvalidArgumentException );
    
    blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    blurProcessor.imageToProcess = nil;
    
    XCTAssertThrowsSpecificNamed( [blurProcessor asyncBlurWithRadius: 1 iterations: 1 cancelingLastOperation: YES], NSException, NSInvalidArgumentException );
}

-( void )test_delegate_being_called_on_new_blurred_images
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    blurProcessor.delegate = self;
    
    [ALDBlurImageProcessorTests fireAsyncBlurOperationWithProcessor: blurProcessor andWaitForControlVariableChange: &successDelegateCalled];
    
    XCTAssertTrue( successDelegateCalled );
}

-( void )test_notification_being_sent_on_new_blurred_images
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    
    [self startListeningToNotifications];
    
    [ALDBlurImageProcessorTests fireAsyncBlurOperationWithProcessor: blurProcessor andWaitForControlVariableChange: &successNotificationSent];
    
    XCTAssertTrue( successNotificationSent );
}

-( void )test_success_block_being_called_on_new_blurred_images
{
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];

    [ALDBlurImageProcessorTests fireAsyncBlurOperationWithProcessor: blurProcessor
                                                       successBlock:^( UIImage *blurredImage ){
                                                           successBlockCalled = YES;
                                                         }
                                                         errorBlock: nil
                                     andWaitForControlVariableChange: &successBlockCalled];
    
    XCTAssertTrue( successBlockCalled );
}

-( void )test_delegate_being_called_on_blur_processing_errors
{
    [makeBlurFailRedefinition startUsingRedefinition];

    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testRetinaImage];
    blurProcessor.delegate = self;
    
    [ALDBlurImageProcessorTests fireAsyncBlurOperationWithProcessor: blurProcessor andWaitForControlVariableChange: &errorDelegateCalled];
    
    XCTAssertTrue( errorDelegateCalled );
}

-( void )test_notification_being_sent_on_blur_processing_errors
{
    [makeBlurFailRedefinition startUsingRedefinition];
    
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testRetinaImage];
    
    [self startListeningToNotifications];
    
    [ALDBlurImageProcessorTests fireAsyncBlurOperationWithProcessor: blurProcessor andWaitForControlVariableChange: &errorNotificationSent];
    
    XCTAssertTrue( errorNotificationSent );
}

-( void )test_error_block_being_called_on_blur_processing_errors
{
    [makeBlurFailRedefinition startUsingRedefinition];
    
    ALDBlurImageProcessor *blurProcessor = [[ALDBlurImageProcessor alloc] initWithImage: testImage];
    
    [ALDBlurImageProcessorTests fireAsyncBlurOperationWithProcessor: blurProcessor
                                                       successBlock: nil
                                                         errorBlock:^( NSNumber *errorCode ){
                                                              errorBlockCalled = YES;
                                                         }
                                     andWaitForControlVariableChange: &errorBlockCalled];
    
    XCTAssertTrue( errorBlockCalled );
}

#pragma mark - ALDBlurImageProcessor Notifications

-( void )onNewBlurredImage:( NSNotification * )notification
{
    successNotificationSent = YES;
}

-( void )onBlurProcessingError:( NSNotification * )notification
{
    errorNotificationSent = YES;
}

#pragma mark - ALDBlurImageProcessorDelegate

-( void )onALDBlurImageProcessor:( ALDBlurImageProcessor * )blurImageProcessor newBlurrredImage:( UIImage * )image
{
    successDelegateCalled = YES;
}

-( void )onALDBlurImageProcessor:( ALDBlurImageProcessor * )blurImageProcessor blurProcessingErrorCode:( NSNumber * )errorCode
{
    errorDelegateCalled = YES;
}

#pragma mark - Test Helpers

+( void )fireAsyncBlurOperationWithProcessor:( ALDBlurImageProcessor * )blurProcessor andWaitForControlVariableChange:( BOOL * )controlVariable
{
    [self fireAsyncBlurOperationWithProcessor: blurProcessor
                                 successBlock: nil
                                   errorBlock: nil
              andWaitForControlVariableChange: controlVariable];
}

+( void )fireAsyncBlurOperationWithProcessor:( ALDBlurImageProcessor * )blurProcessor
                                successBlock:( void(^)( UIImage *blurredImage ) )successBlock
                                  errorBlock:( void(^)( NSNumber *errorCode ) )errorBlock
             andWaitForControlVariableChange:( BOOL * )controlVariable
{
    // Fire the async blur operation from a queue other than the main queue, so we can
    // get its response on the former. This way we can wait for the blur operation on the
    // main queue, which is where the tests run
    [helperOperationQueue addOperationWithBlock:^{
        [blurProcessor asyncBlurWithRadius: 17.0f iterations: 2 successBlock: successBlock errorBlock: errorBlock];
        [NSThread sleepForTimeInterval: 0.5];
    }];
    
    // Guarantees the asyn blur operation ran on the helper queue
    [helperOperationQueue waitUntilAllOperationsAreFinished];
    
    // Try to wait for the blur processor internal queue operatio to run
    int counter = 0;
    while( !( *controlVariable ) )
    {
        [NSThread sleepForTimeInterval: 0.5];
        if( counter++ > 5 )
            break;
    }
    
    // Wait a little longer in case we broke the loop because
    // counter reached its max value
    [helperOperationQueue waitUntilAllOperationsAreFinished];
}

#pragma mark - Helpers

-( void )startListeningToNotifications
{
    [self stopListeningToNotifications];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onNewBlurredImage: )
                                                 name: ALDBlurImageProcessorImageReadyNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onBlurProcessingError: )
                                                 name: ALDBlurImageProcessorImageProcessingErrorNotification
                                               object: nil];
}

-( void )stopListeningToNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: ALDBlurImageProcessorImageReadyNotification
                                                  object: nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: ALDBlurImageProcessorImageProcessingErrorNotification
                                                  object: nil];
}

+( int )comparePixelDataFromImage:( UIImage * )image1 toPixelDataFromImage:( UIImage * )image2
{
    size_t pixelBufferSize;
    void *image1PixelData = [self pixelDataFromImage: image1 pixelBufferSize: &pixelBufferSize];
    void *image2PixelData = [self pixelDataFromImage: image2 pixelBufferSize: nil];
    
    int ret = memcmp( image1PixelData, image2PixelData, pixelBufferSize );
    
    free( image1PixelData );
    free( image2PixelData );
    
    return ret;
}

+( int )comparePixelDataFromImage:( UIImage * )image toPixelData:( const void * )pixelData
{
    size_t pixelBufferSize;
    void *imagePixelData = [self pixelDataFromImage: image pixelBufferSize: &pixelBufferSize];
    
    int ret = memcmp( imagePixelData, pixelData, pixelBufferSize );
    
    free( imagePixelData );
    
    return ret;
}

+( void * )pixelDataFromImage:( UIImage * )image pixelBufferSize:( out size_t * )outPixelBufferSize
{
    CGImageRef imageRef = image.CGImage;
    
    size_t pixelBufferSize = CGImageGetBytesPerRow( imageRef ) * CGImageGetHeight( imageRef );
    void *pixelBuffer = malloc( pixelBufferSize );

    CFDataRef dataSource = CGDataProviderCopyData( CGImageGetDataProvider( imageRef ));
    memcpy( pixelBuffer, CFDataGetBytePtr( dataSource ), pixelBufferSize );
    CFRelease( dataSource );
    
    if( outPixelBufferSize )
        *outPixelBufferSize = pixelBufferSize;
    
    return pixelBuffer;
}

@end














































