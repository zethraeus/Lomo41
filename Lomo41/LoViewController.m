//
//  LoViewController.m
//  Lomo41
//
//  Created by Adam Zethraeus on 12/10/13.
//  Copyright (c) 2013 Very Nice Co. All rights reserved.
//

#import "LoViewController.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVFoundation.h>

#import "LoShotSet.h"

static void * SessionRunningCameraPermissionContext = &SessionRunningCameraPermissionContext;

@interface LoViewController ()
@property (weak, nonatomic) IBOutlet UIView *shootView;
@property (weak, nonatomic) IBOutlet UIButton *shootButton;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic) LoShotSet *currentShots;
@property (nonatomic) id runtimeErrorHandlingObserver;
@property (nonatomic, readonly, getter = isSessionRunningAndHasCameraPermission) BOOL sessionRunningAndHasCameraPermission;
@property (nonatomic) BOOL hasCameraPermission;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) int shotCount;
- (IBAction)doShoot:(id)sender;
@end

@implementation LoViewController

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType
                      preferringPosition:(AVCaptureDevicePosition)position {
	NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
	AVCaptureDevice *captureDevice = [devices firstObject];
	for (AVCaptureDevice *device in devices) {
		if ([device position] == position) {
			captureDevice = device;
			break;
		}
	}
	return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
	if ([device hasFlash] && [device isFlashModeSupported:flashMode])
	{
		NSError *error = nil;
		if ([device lockForConfiguration:&error]) {
			[device setFlashMode:flashMode];
			[device unlockForConfiguration];
		} else {
			NSLog(@"%@", error);
		}
	}
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized {
	return [NSSet setWithObjects:@"session.running", @"hasCameraPermission", nil];
}

- (BOOL)isSessionRunningAndHasCameraPermission {
	return [[self session] isRunning] && [self hasCameraPermission];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.session = [[AVCaptureSession alloc] init];
    self.currentShots = [[LoShotSet alloc] init];
	[self checkCameraPermissions];
	self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
	dispatch_async(self.sessionQueue, ^{
		//[self setBackgroundRecordingID:UIBackgroundTaskInvalid];
		NSError *error = nil;
		AVCaptureDevice *videoDevice = [LoViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        //TODO: lock these for sequential pictures
        if ([videoDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            if ([videoDevice lockForConfiguration:&error]) {
                CGPoint autofocusPoint = CGPointMake(0.5f, 0.5f);
                [videoDevice setFocusPointOfInterest:autofocusPoint];
                [videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                [videoDevice unlockForConfiguration];
            } else {
                NSLog(@"%@", error);
            }
        }
        if ([videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            if ([videoDevice lockForConfiguration:&error]) {
                CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);
                [videoDevice setExposurePointOfInterest:exposurePoint];
                [videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            } else {
                NSLog(@"%@", error);
            }
        }
        [LoViewController setFlashMode:AVCaptureFlashModeOff forDevice:videoDevice];
		AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
		if (error) {
			NSLog(@"%@", error);
		}
		if ([self.session canAddInput:videoDeviceInput]) {
			[self.session addInput:videoDeviceInput];
			self.videoDeviceInput = videoDeviceInput;
		}
		AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
		if ([self.session canAddOutput:stillImageOutput]) {
			[stillImageOutput setOutputSettings:@{AVVideoCodecKey:AVVideoCodecJPEG}];
			[self.session addOutput:stillImageOutput];
			self.stillImageOutput = stillImageOutput;
		}
    });
}

- (void)viewWillAppear:(BOOL)animated {
	dispatch_async(self.sessionQueue, ^{
		[self addObserver:self forKeyPath:@"sessionRunningAndHasCameraPermission" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:SessionRunningCameraPermissionContext];
		__weak LoViewController *weakSelf = self;
		self.runtimeErrorHandlingObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
			LoViewController *strongSelf = weakSelf;
			dispatch_async(strongSelf.sessionQueue, ^{
				// Manually restarting the session since it must have been stopped due to an error.
				[strongSelf.session startRunning];
			});
		}];
		[self.session startRunning];
	});
}

- (void)viewDidDisappear:(BOOL)animated {
	dispatch_async(self.sessionQueue, ^{
		[self.session stopRunning];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
		[[NSNotificationCenter defaultCenter] removeObserver:self.runtimeErrorHandlingObserver];
		[self removeObserver:self forKeyPath:@"sessionRunningAndHasCameraPermission" context:SessionRunningCameraPermissionContext];
	});
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (BOOL)prefersStatusBarHidden {
	return YES;
}

- (BOOL)hasRunningSessionAndCameraPermission {
	return self.session.isRunning && self.hasCameraPermission;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    // enable button based on permission observation
}

- (IBAction)doShoot:(id)sender {
    if (self.timer == nil) {
        self.shotCount = 0;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(shootOnce) userInfo:nil repeats:YES];
    }
}

- (void)shootOnce {
    self.shotCount++;
    bool final = false;
    if (self.shotCount == 4) {
        [self.timer invalidate];
        self.timer = nil;
        final = true;
    }
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        CFRetain(imageDataSampleBuffer);
        dispatch_async(self.sessionQueue, ^{
            if (imageDataSampleBuffer) {
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                [self.currentShots addShot:[[UIImage alloc] initWithData:imageData]];
            }
            CFRelease(imageDataSampleBuffer);
            [self runCaptureAnimation];
            if (final) {
                [self outputToLibrary];
            }
        });
    }];
}

- (void)outputToLibrary {
    dispatch_async(self.sessionQueue, ^{
        if (self.currentShots.count != 4) {
            NSLog(@"Picture count was %lu, did not save to library.", self.currentShots.count);
            return;
        }
        UIImage *firstImage = [self.currentShots.shots objectAtIndex:0];
        UIImage *collage = [LoViewController collageFromImages:self.currentShots.shots];

        [[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[collage CGImage] orientation:(ALAssetOrientation)[firstImage imageOrientation] completionBlock:nil];
        [self.currentShots purge];
    });
}

+ (UIImage *)collageFromImages:(NSArray *)images {
    NSAssert([images count] == 4, @"expecting array of size 4");
    UIImage *firstImage = [images objectAtIndex:0];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(firstImage.size.height, firstImage.size.width), YES, 1.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

	CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);

    NSMutableArray* croppedImages = [NSMutableArray arrayWithCapacity:4];
    for (int i = 0; i < 4; i++){
        UIImage *image = [UIImage imageWithCGImage:[[images objectAtIndex:i] CGImage]
                                             scale:1.0
                                       orientation:UIImageOrientationUp];
        CGRect cropRect = CGRectMake((image.size.width/4.0) + ((image.size.width/8.0) * i), 0, image.size.width/4.0, image.size.height);
        CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], cropRect);
        NSAssert(imageRef != NULL, @"image crop failed");
        UIImage *img = [UIImage imageWithCGImage:imageRef];
        [croppedImages addObject:img];
        CGImageRelease(imageRef);
    }
    for (int i = 0; i < 4; i++) {
        CGContextSaveGState(context);
        UIImage *image = [croppedImages objectAtIndex:i];
        CGRect drawRect = CGRectMake(image.size.width * i, 0, image.size.width, image.size.height);
        CGContextTranslateCTM(context, 0, image.size.height);
        CGContextScaleCTM(context, 1.0, -1.0);
        CGContextDrawImage(context, drawRect, image.CGImage);
        CGContextRestoreGState(context);
    }
    UIImage *collage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return collage;
}

- (void)runCaptureAnimation {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.shootView.layer setOpacity:0.0];
		[UIView animateWithDuration:.25 animations:^{
            [self.shootView.layer setOpacity:1.0];
		}];
	});
}

- (void)checkCameraPermissions {
	NSString *mediaType = AVMediaTypeVideo;
	[AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
		self.hasCameraPermission = granted;
		if (!granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
				[[[UIAlertView alloc] initWithTitle:@"Permission Issue"
											message:@"Lomo41 needs permission to access your camera. Please grant it in settings."
										   delegate:self
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
			});
        }
	}];
}
@end
