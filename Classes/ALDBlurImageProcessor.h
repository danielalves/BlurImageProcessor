//
//  ALDBlurImageProcessor.h
//  ALDBlurImageProcessor
//
//  Created by Daniel L. Alves on 13/03/14.
//  Copyright (c) 2014 Daniel L. Alves. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 *  The userInfo dictionary contains information about the new blurred image. Use the key ALDBlurImageProcessorImageReadyNotificationBlurrredImageKey
 *  to get it.
 */
FOUNDATION_EXPORT NSString * const ALDBlurImageProcessorImageReadyNotification;

/**
 *  The key for an UIImage object, which is the new allocated blurred image.
 */
FOUNDATION_EXPORT NSString * const ALDBlurImageProcessorImageReadyNotificationBlurrredImageKey;

/**
 *  The userInfo dictionary contains information about the blurr processing error. Use the key ALDBlurImageProcessorImageProcessingErrorNotificationErrorKey
 *  to get it.
 */
FOUNDATION_EXPORT NSString * const ALDBlurImageProcessorImageProcessingErrorNotification;

/**
 *  The key for a NSNumber object, which boxes a vImage_Error error code.
 */
FOUNDATION_EXPORT NSString * const ALDBlurImageProcessorImageProcessingErrorNotificationErrorKey;



@class ALDBlurImageProcessor;

/**
 *  The methods declared by the ALDBlurImageProcessorDelegate protocol allow the adopting delegate to respond to messages from the ALDBlurImageProcessor class.
 */
@protocol ALDBlurImageProcessorDelegate< NSObject >

    @optional
        /**
         *  Tells the delegate when a blurr processing error has occurred.
         *
         *  @param blurImageProcessor The object which generated the call.
         *  @param error              A NSNumber object boxing a vImage_Error error code.
         */
        -( void )onALDBlurImageProcessor:( ALDBlurImageProcessor * )blurImageProcessor blurProcessingError:( NSNumber * )error;

        /**
         *  Tells the delegate when a new blurred image has been generated.
         *
         *  @param blurImageProcessor The object which generated the call.
         *  @param image              The new allocated blurred image.
         */
        -( void )onALDBlurImageProcessor:( ALDBlurImageProcessor * )blurImageProcessor newBlurrredImage:( UIImage * )image;
@end



/**
 *  ALDBlurImageProcessor offers a very easy and practical way to generate blurred images in real time. After an image
 *  is specified to be targeted by it, every new blur operation will create a new allocated image. Varying the value of 
 *  radiuses and iterations, its possible to create many different results and even animations.
 *
 *  Blur operations can be synchronous and asynchronous. Synchronous operations run on the thread/operation queue from which they
 *  were called. Each ALDBlurImageProcessor object has its own processing queue to run asynchronous operations, so it it easy to 
 *  manage them. Besides that, all delegate callbacks and notifications are called/fired on the main thread, so there's no need to
 *  worry about using the new blurred images passed as parameters directly into the user interface.
 *
 *  ALDBlurImageProcessor tries to achieve a good balance between memory and performance. It also listens to 
 *  UIApplicationDidReceiveMemoryWarningNotification notifications to clean temporary internal buffers on low memory conditions.
 */
@interface ALDBlurImageProcessor : NSObject

/**
 *  The image which will be targeted by blur operations. This can be changed after
 *  the object has been created with no side effects.
 */
@property( nonatomic, readwrite, strong )UIImage *imageToProcess;

/**
 *  The delegate of the ALDBlurImageProcessor object. The delegate must adopt the ALDBlurImageProcessorDelegate protocol.
 */
@property( nonatomic, readwrite, weak )id< ALDBlurImageProcessorDelegate > delegate;

/**
 *  Initializes and returns a newly allocated ALDBlurImageProcessor object targeting the specified image.
 *
 *  @param image The image which will be targeted by blur operations.
 *
 *  @return An initialized ALDBlurImageProcessor object or nil if the object couldn't be created.
 */
-( instancetype )initWithImage:( UIImage * )image;

/**
 *  Generated a new allocated blurred image synchronously. This method only calls the delegate/fires notifications in error cases.
 *
 *  @param radius              The radius of the blur, specifying how many pixels will be considered when generating the output pixel
 *                             value. For algorithm reasons, this must be an odd number. If you pass an even number, it will be increased
 *                             by 1. If radius is equal to zero, no blur will happen and the original image will be passed as the result.
 *
 *  @param nIterations         The number of times radius will be applied to the image. The higher nIterations is, the slower
 *                             the output will be generated. Varying the number of iterations, combined with a static value of
 *                             radius, typically create a smoother blurred image than just increasing the radius value. If nIterations
 *                             is equal to zero, no blur will happen and the original image will be passed as the result.
 *
 *  @return A new allocated blurred image
 *
 *  @throws NSInvalidArgumentException if imageToProcess is nil
 *
 *  @see asyncBlurWithRadius:andIterations:
 *  @see asyncBlurWithRadius:andIterations:cancelingLastOperation:
 */
-( UIImage * )syncBlurWithRadius:( uint32_t )radius andIterations:( uint8_t )nIterations;

/**
 *  This is the same as calling asyncBlurWithRadius:andIterations:cancelingLastOperation: with
 *  cancelingLastOperation equal to NO.
 *
 *  @param radius              The radius of the blur, specifying how many pixels will be considered when generating the output pixel
 *                             value. For algorithm reasons, this must be an odd number. If you pass an even number, it will be increased
 *                             by 1. If radius is equal to zero, no blur will happen and the original image will be passed as the result.
 *
 *  @param nIterations         The number of times radius will be applied to the image. The higher nIterations is, the slower
 *                             the output will be generated. Varying the number of iterations, combined with a static value of
 *                             radius, typically create a smoother blurred image than just increasing the radius value. If nIterations
 *                             is equal to zero, no blur will happen and the original image will be passed as the result.
 *
 *  @throws NSInvalidArgumentException if imageToProcess is nil
 *
 *  @see syncBlurWithRadius:andIterations:
 *  @see asyncBlurWithRadius:andIterations:cancelingLastOperation:
 *  @see cancelAsyncBlurOperations
 */
-( void )asyncBlurWithRadius:( uint32_t )radius andIterations:( uint8_t )nIterations;

/**
 *  Queues an asynchronous blur operation, targeting imageToProcess, on this object operation queue. When the new 
 *  blurred image is ready, calls the delegate and fires the respective notification on the main thread.
 *
 *  @param radius              The radius of the blur, specifying how many pixels will be considered when generating the output pixel
 *                             value. For algorithm reasons, this must be an odd number. If you pass an even number, it will be increased
 *                             by 1. If radius is equal to zero, no blur will happen and the original image will be passed as the result.
 *
 *  @param nIterations         The number of times radius will be applied to the image. The higher nIterations is, the slower
 *                             the output will be generated. Varying the number of iterations, combined with a static value of
 *                             radius, typically create a smoother blurred image than just increasing the radius value. If nIterations
 *                             is equal to zero, no blur will happen and the original image will be passed as the result.
 *
 *  @param cancelLastOperation YES if the last queued asynchronous blur operation should be canceled. NO otherwise. If there is
 *                             no asynchronous blur operation queued or all of them have already been processed, cancelLastOperation
 *                             is ignored. This parameter is useful when there's a need to opt between generating all blur operations 
 *                             ouputs or just having the last blur operation output as fast as possible.
 *
 *  @throws NSInvalidArgumentException if imageToProcess is nil
 *
 *  @see syncBlurWithRadius:andIterations:
 *  @see asyncBlurWithRadius:andIterations:
 *  @see cancelAsyncBlurOperations
 */
-( void )asyncBlurWithRadius:( uint32_t )radius andIterations:( uint8_t )nIterations cancelingLastOperation:( BOOL )cancelLastOperation;

/**
 *  Cancels all asynchronous blur operations queued by previous calls to asyncBlurWithRadius:andIterations:
 *  and/or asyncBlurWithRadius:andIterations:cancelingLastOperation:
 *
 *  @see asyncBlurWithRadius:andIterations:
 *  @see asyncBlurWithRadius:andIterations:cancelingLastOperation:
 */
-( void )cancelAsyncBlurOperations;

@end
