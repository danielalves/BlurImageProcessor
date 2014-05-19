//
//  ALDBlurImageProcessor.m
//  ALDBlurImageProcessor
//
//  Created by Daniel L. Alves on 13/03/14.
//  Copyright (c) 2014 Daniel L. Alves. All rights reserved.
//

#import "ALDBlurImageProcessor.h"

// ios
#import <Accelerate/Accelerate.h>

#pragma mark - Macros

// Just to get compilation errors and be refactoring compliant. But this way we can't concat strings at compilation time =/
#define EVAL_AND_STRINGIFY(x) (x ? __STRING(x) : __STRING(x))

#pragma mark - Notification Consts

NSString * const ALDBlurImageProcessorImageReadyNotification = @"ald.blur-image-processor.image-ready";
NSString * const ALDBlurImageProcessorImageReadyNotificationBlurrredImageKey = @"ald.blur-image-processor.image-ready.blurred-image";

NSString * const ALDBlurImageProcessorImageProcessingErrorNotification = @"ald.blur-image-processor.image-processing-error";
NSString * const ALDBlurImageProcessorImageProcessingErrorNotificationErrorKey = @"ald.blur-image-processor.image-processing-error.error-key";

#pragma mark - Class Extension

@interface ALDBlurImageProcessor()
{
    NSOperationQueue *imageBlurProcessingQueue;
    
    vImage_Buffer originalImageBuffer;
    vImage_Buffer processedImageBuffer;
    vImage_Buffer tempImageBuffer;
    
    NSBlockOperation *lastOperation;
}
@end

#pragma mark - Implementation

@implementation ALDBlurImageProcessor

#pragma mark - Accessors

-( void )setImageToProcess:( UIImage * )newImageToProcess
{
    @synchronized( self )
    {
        if( newImageToProcess != _imageToProcess )
        {
            _imageToProcess = newImageToProcess;
            [self initBlurProcessingBuffers];
        }
    }
}

#pragma mark - Ctors & Dtor

-( id )init
{
    self = [super init];
    if( self )
    {
        memset( &originalImageBuffer, 0, sizeof( vImage_Buffer ));
        memset( &processedImageBuffer, 0, sizeof( vImage_Buffer ));
        memset( &tempImageBuffer, 0, sizeof( vImage_Buffer ));
        
        imageBlurProcessingQueue = [NSOperationQueue new];
		imageBlurProcessingQueue.name = [NSString stringWithFormat: @"NTBlurImageProcessorProcessingQueue (%@)", self];
        
        // We need blur operations to run in the same order they were queued. Afterall, if
        // we are generating many blurred versions of the same image, we want to return
        // them in order
		imageBlurProcessingQueue.maxConcurrentOperationCount = 1;
        
        [self startListeningToMemoryWarnings];
    }
    return self;
}

-( instancetype )initWithImage:( UIImage * )image
{
    self = [self init];
    if( self )
        self.imageToProcess = image;

    return self;
}

-( void )dealloc
{
    [self stopListeningToMemoryWarnings];
    
    [self cancelAsyncBlurOperations];
    [self freeBlurProcessingBuffers];
}

#pragma mark - UIApplication Notifications Management

-( void )startListeningToMemoryWarnings
{
    [self stopListeningToMemoryWarnings];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector( onMemoryWarning )
                                                 name: UIApplicationDidReceiveMemoryWarningNotification
                                               object: [UIApplication sharedApplication]];
}

-( void )stopListeningToMemoryWarnings
{
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: UIApplicationDidReceiveMemoryWarningNotification
                                                  object: [UIApplication sharedApplication]];
}

#pragma mark - Memory Management

-( void )onMemoryWarning
{
    [self freeTempBuffer];
}

-( void )freeBlurProcessingBuffers
{
    @synchronized( self )
    {
        if( originalImageBuffer.data )
        {
            free( originalImageBuffer.data );
            originalImageBuffer.data = nil;
        }
        
        if( processedImageBuffer.data )
        {
            free( processedImageBuffer.data );
            processedImageBuffer.data = nil;
        }
        
        [self freeTempBuffer];
    }
}

-( void )freeTempBuffer
{
    @synchronized( self )
    {
        if( tempImageBuffer.data )
        {
            free( tempImageBuffer.data );
            tempImageBuffer.data = nil;
        }
    }
}

-( void )initBlurProcessingBuffers
{
    @synchronized( self )
    {
        [self freeBlurProcessingBuffers];
        
        if( !_imageToProcess )
            return;
        
        CGImageRef imageRef = _imageToProcess.CGImage;
        [self initBlurProcessingBuffer: &originalImageBuffer forImage: imageRef];
        [self initBlurProcessingBuffer: &processedImageBuffer forImage: imageRef];
        [self initBlurProcessingBuffer: &tempImageBuffer forImage: imageRef];
        
        CFDataRef dataSource = CGDataProviderCopyData( CGImageGetDataProvider( imageRef ));
        memcpy( originalImageBuffer.data, CFDataGetBytePtr( dataSource ), originalImageBuffer.rowBytes * originalImageBuffer.height );
        memcpy( processedImageBuffer.data, CFDataGetBytePtr( dataSource ), processedImageBuffer.rowBytes * processedImageBuffer.height );
        CFRelease( dataSource );
    }
}

-( void )initBlurProcessingBuffer:( vImage_Buffer * )buffer forImage:( CGImageRef )image
{
    buffer->width = CGImageGetWidth( image );
    buffer->height = CGImageGetHeight( image );
    buffer->rowBytes = CGImageGetBytesPerRow( image );
    buffer->data = malloc( buffer->rowBytes * buffer->height );
}

#pragma mark - Blur Processing

-( UIImage * )blurImage:( UIImage * )originalImage
             withRadius:( uint32_t )radius
          andIterations:( uint8_t )nIterations
{
    UIImage *finalImage = nil;
    
    @synchronized( self )
    {
        if( _imageToProcess )
        {
            vImage_Buffer finalImageBuffer;
            if( nIterations == 0 || radius == 0 )
            {
                finalImageBuffer = originalImageBuffer;
            }
            else
            {
                // Maybe we have freed memory on a memory warning notification, so we need to check it
                if( !tempImageBuffer.data )
                    tempImageBuffer.data = malloc( tempImageBuffer.rowBytes * tempImageBuffer.height );
                
                // If we couldn't allocate memory, we'll be sorry, but we'll return the last image we generated
                // If we never generated a blurred image, that will be the original image
                if( tempImageBuffer.data )
                {
                    // Radius must be an odd integer, or we'll get a kvImageInvalidKernelSize error. See
                    // vImageBoxConvolve_ARGB8888 documentation for a better discussion
                    uint32_t finalRadius = ( uint32_t )( radius * originalImage.scale );
                    if(( finalRadius & 1 ) == 0 )
                        ++finalRadius;
                    
                    // We must never lose the original image, so we can generated any number of blurred versions
                    // out of it. This is why we copy its data to tempImageBuffer before proceeding
                    memcpy( tempImageBuffer.data, originalImageBuffer.data, originalImageBuffer.rowBytes * originalImageBuffer.height );

                    // The reason of the loop below is that many convolve iterations generate a better blurred image
                    // than applying a greater convolve radius
                    for( uint16_t i = 0 ; i < nIterations ; ++i )
                    {
                        vImage_Error error = vImageBoxConvolve_ARGB8888( &tempImageBuffer, &processedImageBuffer, NULL, 0, 0, finalRadius, finalRadius, NULL, kvImageEdgeExtend );
                        if( error != kvImageNoError )
                        {
                            [self notifyError: error];
                            break;
                        }

                        void *temp = tempImageBuffer.data;
                        tempImageBuffer.data = processedImageBuffer.data;
                        processedImageBuffer.data = temp;
                    }
                    
                    // The last processed image is being hold by tempImageBuffer. So let's fix it
                    // by swaping buffers again
                    void *temp = tempImageBuffer.data;
                    tempImageBuffer.data = processedImageBuffer.data;
                    processedImageBuffer.data = temp;
                }
                
                finalImageBuffer = processedImageBuffer;
            }
            
            CGContextRef finalImageContext = CGBitmapContextCreate( finalImageBuffer.data,
                                                                    finalImageBuffer.width,
                                                                    finalImageBuffer.height,
                                                                    8,
                                                                    finalImageBuffer.rowBytes,
                                                                    CGImageGetColorSpace( originalImage.CGImage ),
                                                                    CGImageGetBitmapInfo( originalImage.CGImage ));
            
            // TODO : Here we could call a delegate with the context, so we could do a post process. Or
            // we could receive a block to do the same
            // ...
            
            CGImageRef finalImageRef = CGBitmapContextCreateImage( finalImageContext );
            finalImage = [UIImage imageWithCGImage: finalImageRef scale: originalImage.scale orientation: originalImage.imageOrientation];
            CGImageRelease( finalImageRef );
            CGContextRelease( finalImageContext );
        }
    }
    
    return finalImage;
}

-( void )notifyError:( vImage_Error )error
{
    NSBlockOperation *errorNotificationOperation = [NSBlockOperation new];
    
    __weak ALDBlurImageProcessor *weakSelf = self;
    __weak NSBlockOperation *weakErrorNotificationOperation = errorNotificationOperation;
    
    [errorNotificationOperation addExecutionBlock: ^{
        
        if( weakErrorNotificationOperation.isCancelled )
            return;
        
        if( [weakSelf.delegate respondsToSelector: @selector( onALDBlurImageProcessor:blurProcessingError: )] )
            [weakSelf.delegate onALDBlurImageProcessor: weakSelf blurProcessingError: @( error )];
        
        [[NSNotificationCenter defaultCenter] postNotificationName: ALDBlurImageProcessorImageProcessingErrorNotification
                                                            object: weakSelf
                                                          userInfo: @{ ALDBlurImageProcessorImageProcessingErrorNotificationErrorKey: @( error ) }];
    }];
    
    [[NSOperationQueue mainQueue] addOperations: @[ errorNotificationOperation ] waitUntilFinished: YES];
}

-( UIImage * )syncBlurWithRadius:( uint32_t )radius andIterations:( uint8_t )nIterations
{
    if( !_imageToProcess )
        [NSException raise: NSInvalidArgumentException format: @"%s must not be nil", EVAL_AND_STRINGIFY(_imageToProcess)];
    
    return [self blurImage: _imageToProcess
                withRadius: radius
             andIterations: nIterations];
}

-( void )asyncBlurWithRadius:( uint32_t )radius andIterations:( uint8_t )nIterations
{
    [self asyncBlurWithRadius: radius andIterations: nIterations cancelingLastOperation: NO];
}

-( void )asyncBlurWithRadius:( uint32_t )radius andIterations:( uint8_t )nIterations cancelingLastOperation:( BOOL )cancelLastOperation
{
    if( !_imageToProcess )
        [NSException raise: NSInvalidArgumentException format: @"%s must not be nil", EVAL_AND_STRINGIFY(_imageToProcess)];
    
    if( cancelLastOperation )
        [lastOperation cancel];
    
    NSBlockOperation *operation = [[NSBlockOperation alloc] init];
    
    __weak NSBlockOperation *weakOperation = operation;
    __weak ALDBlurImageProcessor *weakSelf = self;
    
    [operation addExecutionBlock:^{

        UIImage *blurredImage = [weakSelf blurImage: _imageToProcess
                                         withRadius: radius
                                      andIterations: nIterations];
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
            if( weakOperation.isCancelled )
                return;
            
            if( [weakSelf.delegate respondsToSelector: @selector( onALDBlurImageProcessor:newBlurrredImage: )] )
                [weakSelf.delegate onALDBlurImageProcessor: weakSelf newBlurrredImage: blurredImage];
            
            [[NSNotificationCenter defaultCenter] postNotificationName: ALDBlurImageProcessorImageReadyNotification
                                                                object: weakSelf
                                                              userInfo: @{ ALDBlurImageProcessorImageReadyNotificationBlurrredImageKey: blurredImage }];
        }];
    }];
    
    // TODO : These 2 NSBlockOperation properties, queuePriority and threadPriority, could
    // be parameterized
    operation.queuePriority = NSOperationQueuePriorityVeryHigh;
    operation.threadPriority = 1.0f;
    
    [imageBlurProcessingQueue addOperation: operation];
    
    lastOperation = operation;
}

#pragma mark - NSOperationQueue Management

-( void )cancelAsyncBlurOperations
{
    [imageBlurProcessingQueue cancelAllOperations];
}

@end












































