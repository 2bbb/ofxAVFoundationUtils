/*
 *  ofxAVFoundationGrabberEx.mm
 */

#include "ofxAVFoundationGrabberEx.h"
#include "ofVec2f.h"
#include "ofRectangle.h"
#include "ofGLUtils.h"

#import <Accelerate/Accelerate.h>

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

#include "ofxAVFoundationUtilityFunctions.h"

#define grabber ((OSXVideoGrabberEx *)grabber_)

class GrabberEx;

@interface OSXVideoGrabberEx : NSObject <
    AVCaptureVideoDataOutputSampleBufferDelegate
> {
    
@public
    CGImageRef currentFrame;
    
    int width;
    int height;
    
    BOOL bInitCalled;
    int deviceID;
    
    AVCaptureDeviceInput        *captureInput;
    AVCaptureVideoDataOutput    *captureOutput;
    AVCaptureDevice             *device;
    AVCaptureSession            *captureSession;
    
    ofxAVFoundationGrabberEx *grabberPtr;
}

- (BOOL)setupCapture:(int)framerate capWidth:(int)w capHeight:(int)h;
- (void)startCapture;
- (void)stopCapture;
- (void)lockExposureAndFocus;
- (std::vector <std::string>)listDevices;
- (void)setDevice:(int)device_;
- (void)eraseGrabberPtr;

-(CGImageRef)getCurrentFrame;

@end

@interface OSXVideoGrabberEx ()
@property (nonatomic, retain) AVCaptureSession *captureSession;
@end

@implementation OSXVideoGrabberEx
@synthesize captureSession;

#pragma mark -
#pragma mark Initialization
- (id)init {
	self = [super init];
	if (self) {
		captureInput = nil;
		captureOutput = nil;
		device = nil;

		bInitCalled = NO;
		grabberPtr = NULL;
		deviceID = 0;
        width = 0;
        height = 0;
        currentFrame = 0;
	}
	return self;
}

- (AVCaptureDevice *)createDevice {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    if(devices.count == 0) return nil;
    if(devices.count <= deviceID) {
        deviceID = devices.count - 1;
    }
    return devices[deviceID];
}

- (BOOL)setupCapture:(int)framerate capWidth:(int)w capHeight:(int)h {
    device = [self createDevice];
    
	if(device) {
		NSError *error = nil;
		[device lockForConfiguration:&error];

		if(!error) {

			float smallestDist = 99999999.0;
			int bestW, bestH = 0;

			// Set width and height to be passed in dimensions
			// We will then check to see if the dimensions are supported and if not find the closest matching size.
			width = w;
			height = h;

			ofVec2f requestedDimension(width, height);

			AVCaptureDeviceFormat * bestFormat  = nullptr;
			for ( AVCaptureDeviceFormat * format in [device formats] ) {
				CMFormatDescriptionRef desc = format.formatDescription;
				CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);

				int tw = dimensions.width;
				int th = dimensions.height;
				ofVec2f formatDimension(tw, th);

				if( tw == width && th == height ){
					bestW = tw;
					bestH = th;
					bestFormat = format;
					break;
				}

				float dist = (formatDimension-requestedDimension).length();
				if( dist < smallestDist ){
					smallestDist = dist;
					bestW = tw;
					bestH = th;
					bestFormat = format;
				}

				ofLogVerbose("GrabberEx") << " supported dimensions are: " << dimensions.width << " " << dimensions.height;
			}

			// Set the new dimensions and format
			if( bestFormat != nullptr && bestW != 0 && bestH != 0 ){
				if( bestW != width || bestH != height ){
					ofLogWarning("GrabberEx") << " requested width and height aren't supported. Setting capture size to closest match: " << bestW << " by " << bestH<< std::endl;
				}

				[device setActiveFormat:bestFormat];
				width = bestW;
				height = bestH;
			}

			//only set the framerate if it has been set by the user
			if( framerate > 0 ){

				AVFrameRateRange * desiredRange = nil;
				NSArray * supportedFrameRates = device.activeFormat.videoSupportedFrameRateRanges;

				int numMatch = 0;
				for(AVFrameRateRange * range in supportedFrameRates){

					if( (floor(range.minFrameRate) <= framerate && ceil(range.maxFrameRate) >= framerate) ) {
						ofLogVerbose("GrabberEx") << "found good framerate range, min: " << range.minFrameRate << " max: " << range.maxFrameRate << " for requested fps: " << framerate;
						desiredRange = range;
						numMatch++;
					}
				}

				if( numMatch > 0 ){
					//TODO: this crashes on some devices ( Orbecc Astra Pro )
					device.activeVideoMinFrameDuration = desiredRange.minFrameDuration;
					device.activeVideoMaxFrameDuration = desiredRange.maxFrameDuration;
				}else{
					ofLogError("GrabberEx") << " could not set framerate to: " << framerate << ". Device supports: ";
					for(AVFrameRateRange * range in supportedFrameRates){
						ofLogError() << "  framerate range of: " << range.minFrameRate <<
					 " to " << range.maxFrameRate;
					 }
				}

			}

			[device unlockForConfiguration];
		} else {
			NSLog(@"OSXVideoGrabberEx Init Error: %@", error);
		}
        
		// We setup the input
		captureInput						= [AVCaptureDeviceInput
											   deviceInputWithDevice:device
											   error:nil];

		// We setup the output
		captureOutput = [[AVCaptureVideoDataOutput alloc] init];
		// While a frame is processes in -captureOutput:didOutputSampleBuffer:fromConnection: delegate methods no other frames are added in the queue.
		// If you don't want this behaviour set the property to NO
		captureOutput.alwaysDiscardsLateVideoFrames = YES;



		// We create a serial queue to handle the processing of our frames
		dispatch_queue_t queue;
		queue = dispatch_queue_create("cameraQueue", NULL);
		[captureOutput setSampleBufferDelegate:self queue:queue];
		dispatch_release(queue);

		NSDictionary* videoSettings =[NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithDouble:width], (id)kCVPixelBufferWidthKey,
                              [NSNumber numberWithDouble:height], (id)kCVPixelBufferHeightKey,
                              [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA], (id)kCVPixelBufferPixelFormatTypeKey,
                              nil];
		[captureOutput setVideoSettings:videoSettings];

		// And we create a capture session
		if(self.captureSession) {
            [self.captureSession release];
			self.captureSession = nil;
		}
		self.captureSession = [[AVCaptureSession alloc] init];

		[self.captureSession beginConfiguration];

		// We add input and output
		[self.captureSession addInput:captureInput];
		[self.captureSession addOutput:captureOutput];

		// We specify a minimum duration for each frame (play with this settings to avoid having too many frames waiting
		// in the queue because it can cause memory issues). It is similar to the inverse of the maximum framerate.
		// In this example we set a min frame duration of 1/10 seconds so a maximum framerate of 10fps. We say that
		// we are not able to process more than 10 frames per second.
		// Called after added to captureSession

		AVCaptureConnection *conn = [captureOutput connectionWithMediaType:AVMediaTypeVideo];
		if ([conn isVideoMinFrameDurationSupported] == YES &&
			[conn isVideoMaxFrameDurationSupported] == YES) {
				[conn setVideoMinFrameDuration:CMTimeMake(1, framerate)];
				[conn setVideoMaxFrameDuration:CMTimeMake(1, framerate)];
		}

		// We start the capture Session
		[self.captureSession commitConfiguration];
		[self.captureSession startRunning];

		bInitCalled = YES;
		return YES;
	}
	return NO;
}

-(void)startCapture{

	[self.captureSession startRunning];

	[captureInput.device lockForConfiguration:nil];

	//if( [captureInput.device isExposureModeSupported:AVCaptureExposureModeAutoExpose] ) [captureInput.device setExposureMode:AVCaptureExposureModeAutoExpose ];
	if( [captureInput.device isFocusModeSupported:AVCaptureFocusModeAutoFocus] )	[captureInput.device setFocusMode:AVCaptureFocusModeAutoFocus ];

}

-(void)lockExposureAndFocus{

	[captureInput.device lockForConfiguration:nil];

	//if( [captureInput.device isExposureModeSupported:AVCaptureExposureModeLocked] ) [captureInput.device setExposureMode:AVCaptureExposureModeLocked ];
	if( [captureInput.device isFocusModeSupported:AVCaptureFocusModeLocked] )	[captureInput.device setFocusMode:AVCaptureFocusModeLocked ];


}

-(void)stopCapture{
	if(self.captureSession) {
		if(captureOutput){
			if(captureOutput.sampleBufferDelegate != nil) {
				[captureOutput setSampleBufferDelegate:nil queue:NULL];
			}
		}

		// remove the input and outputs from session
		for(AVCaptureInput *input1 in self.captureSession.inputs) {
		    [self.captureSession removeInput:input1];
		}
		for(AVCaptureOutput *output1 in self.captureSession.outputs) {
		    [self.captureSession removeOutput:output1];
		}

		[self.captureSession stopRunning];
	}
}

-(CGImageRef)getCurrentFrame{
	return currentFrame;
}

-(std::vector <std::string>)listDevices {
    std::vector <std::string> deviceNames;
	NSArray * devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	int i = 0;
	for(AVCaptureDevice * captureDevice in devices){
        deviceNames.push_back(captureDevice.localizedName.UTF8String);
		 ofLogNotice() << "Device: " << i << ": " << deviceNames.back();
		i++;
    }
    return deviceNames;
}

-(void)setDevice:(int)device_ {
	deviceID = device_;
}

#pragma mark -
#pragma mark AVCaptureSession delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	   fromConnection:(AVCaptureConnection *)connection
{
	if(grabberPtr != NULL) {
		@autoreleasepool {
			CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
			// Lock the image buffer
			CVPixelBufferLockBaseAddress(imageBuffer,0);

			if( grabberPtr != NULL && !grabberPtr->bLock ){

				unsigned char *isrc4 = (unsigned char *)CVPixelBufferGetBaseAddress(imageBuffer);
				size_t widthIn  = CVPixelBufferGetWidth(imageBuffer);
				size_t heightIn	= CVPixelBufferGetHeight(imageBuffer);

				if( widthIn != grabberPtr->getWidth() || heightIn != grabberPtr->getHeight() ){
					ofLogError("GrabberEx") << " incoming image dimensions " << widthIn << " by " << heightIn << " don't match. This shouldn't happen! Returning.";
					return;
				}

				if( grabberPtr->pixelFormat == OF_PIXELS_BGRA ){

					if( grabberPtr->capMutex.try_lock() ){
						grabberPtr->pixelsTmp.setFromPixels(isrc4, widthIn, heightIn, 4);
						grabberPtr->updatePixelsCB();
						grabberPtr->capMutex.unlock();
					}

				}else{

					ofPixels rgbConvertPixels;
					rgbConvertPixels.allocate(widthIn, heightIn, 3);

					vImage_Buffer srcImg;
					srcImg.width = widthIn;
					srcImg.height = heightIn;
					srcImg.data = isrc4;
					srcImg.rowBytes = CVPixelBufferGetBytesPerRow(imageBuffer);

					vImage_Buffer dstImg;
					dstImg.width = srcImg.width;
					dstImg.height = srcImg.height;
					dstImg.rowBytes = width*3;
					dstImg.data = rgbConvertPixels.getData();

					vImage_Error err;
					err = vImageConvert_BGRA8888toRGB888(&srcImg, &dstImg, kvImageNoFlags);
					if(err != kvImageNoError){
						ofLogError("GrabberEx") << "Error using accelerate to convert bgra to rgb with vImageConvert_BGRA8888toRGB888 error: " << err;
					}else{

						if( grabberPtr->capMutex.try_lock() ){
							grabberPtr->pixelsTmp = rgbConvertPixels;
							grabberPtr->updatePixelsCB();
							grabberPtr->capMutex.unlock();
						}

					}
				}

                // Unlock the image buffer
                CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

			}
		}
	}
}

#pragma mark -
#pragma mark Memory management

- (void)dealloc {
	// Stop the CaptureSession
	if(self.captureSession) {
		[self stopCapture];
		self.captureSession = nil;
	}
	if(captureOutput){
		if(captureOutput.sampleBufferDelegate != nil) {
			[captureOutput setSampleBufferDelegate:nil queue:NULL];
		}
        [captureOutput release];
		captureOutput = nil;
	}

	captureInput = nil;
	device = nil;

	if(grabberPtr) {
		[self eraseGrabberPtr];
	}
	grabberPtr = nil;
	if(currentFrame) {
		// release the currentFrame image
		CGImageRelease(currentFrame);
		currentFrame = nil;
	}
    [super dealloc];
}

- (void)eraseGrabberPtr {
	grabberPtr = NULL;
}

@end

namespace ofx {
    namespace AVFoundationUtils {
        GrabberEx::GrabberEx(){
            fps		= -1;
            grabber_ = nil;
            width = 0;
            height = 0;
            bIsInit = false;
            pixelFormat = OF_PIXELS_RGB;
            newFrame = false;
            bHavePixelsChanged = false;
            bLock = false;
        }

        GrabberEx::~GrabberEx(){
            ofLog(OF_LOG_VERBOSE, "GrabberEx destructor");
            close();
        }

        void GrabberEx::clear(){
            if( pixels.size() ){
                pixels.clear();
                pixelsTmp.clear();
            }
        }

        void GrabberEx::close(){
            bLock = true;
            if(grabber) {
                // Stop and release the the OSXVideoGrabberEx
                [grabber stopCapture];
                [grabber eraseGrabberPtr];
                [grabber release];
                grabber_ = nil;
            }
            clear();
            bIsInit = false;
            width = 0;
            height = 0;
            fps		= -1;
            pixelFormat = OF_PIXELS_RGB;
            newFrame = false;
            bHavePixelsChanged = false;
            bLock = false;
        }

        void GrabberEx::setDesiredFrameRate(int capRate){
            fps = capRate;
        }

        bool GrabberEx::setup(int w, int h){

            if( grabber_ == nil ){
                grabber_ = [[OSXVideoGrabberEx alloc] init];
            }

            grabber->grabberPtr = this;

            if([grabber setupCapture:fps capWidth:w capHeight:h]) {
                //update the pixel dimensions based on what the camera supports
                width = grabber->width;
                height = grabber->height;

                clear();
                
                pixels.allocate(width, height, pixelFormat);
                pixelsTmp.allocate(width, height, pixelFormat);

                [grabber startCapture];

                newFrame=false;
                bIsInit = true;

                return true;
            } else {
                return false;
            }
        }


        bool GrabberEx::isInitialized() const{
            return bIsInit;
        }

        void GrabberEx::update(){
            newFrame = false;

            if(bHavePixelsChanged) {
                std::lock_guard<std::mutex> _{capMutex};
                pixels = pixelsTmp;
                bHavePixelsChanged = false;
                newFrame = true;
            }
        }

        ofPixels & GrabberEx::getPixels(){
            return pixels;
        }

        const ofPixels & GrabberEx::getPixels() const{
            return pixels;
        }

        bool GrabberEx::isFrameNew() const{
            return newFrame;
        }

        void GrabberEx::updatePixelsCB(){
            //TODO: does this need a mutex? or some thread protection?
            bHavePixelsChanged = true;
        }

        std::vector <ofVideoDevice> GrabberEx::listDevices() const{
            std::vector <std::string> devList = [grabber listDevices];

            std::vector <ofVideoDevice> devices;
            for(int i = 0; i < devList.size(); i++){
                ofVideoDevice vd;
                vd.deviceName = devList[i];
                vd.id = i;
                vd.bAvailable = true;
                devices.push_back(vd);
            }

            return devices;
        }

        void GrabberEx::setDeviceID(int deviceID) {
            if(grabber_ == nil) {
                grabber_ = [[OSXVideoGrabberEx alloc] init];
            }
            [grabber setDevice:deviceID];
            device = deviceID;
        }

        void GrabberEx::setDeviceUniqueID(const std::string &uniqueID) {
            setDeviceID(getDeviceIDByUniqueID(uniqueID));
        }

        int GrabberEx::getDeviceIDByUniqueID(const std::string &uniqueID) const {
            return ofx::AVFoundationUtils::getDeviceIDFromUniqueID(uniqueID);
        }

        bool GrabberEx::setPixelFormat(ofPixelFormat PixelFormat) {
            if(PixelFormat == OF_PIXELS_RGB){
                pixelFormat = PixelFormat;
                return true;
            } else if(PixelFormat == OF_PIXELS_RGBA){
                pixelFormat = PixelFormat;
                return true;
            } else if(PixelFormat == OF_PIXELS_BGRA){
                pixelFormat = PixelFormat;
                return true;
            }
            return false;
        }

        ofPixelFormat GrabberEx::getPixelFormat() const{
            return pixelFormat;
        }

        namespace bbb {
            struct avcapturedevice_configure_lock {
                avcapturedevice_configure_lock(AVCaptureDevice *device) {
                    this->device = device;
                    NSError *err = nil;
                    [this->device lockForConfiguration:&err];
                    if(err) {
                        ofLogError("GrabberEx") << err.description.UTF8String;
                    }
                }
                ~avcapturedevice_configure_lock() {
                    [device unlockForConfiguration];
                }
                AVCaptureDevice *device;
            };
        };

#define Device (grabber->device)
#define IfNullDevice(...)\
        if(grabber_ == nil || Device == nil) {\
            ofLogWarning("GrabberEx") << "device is not initialized?";\
            return __VA_ARGS__;\
        }
#define Lock bbb::avcapturedevice_configure_lock avcapturedevice_configure_lock{Device};

        std::string GrabberEx::getUniqueID() const {
            IfNullDevice("");
            return Device.uniqueID.UTF8String;
        }

        std::string GrabberEx::getModelID() const {
            IfNullDevice("");
            return Device.modelID.UTF8String;
        }

        std::string GrabberEx::getManufacturer() const {
            IfNullDevice("");
            return Device.manufacturer.UTF8String;
        }

        std::string GrabberEx::getLocalizedName() const {
            IfNullDevice("");
            return Device.localizedName.UTF8String;
        }

        bool GrabberEx::adjustingExposure() const {
            IfNullDevice(false);
            return Device.adjustingExposure;
        }

        CaptureExposureMode GrabberEx::exposureMode() const {
            IfNullDevice((CaptureExposureMode)0);
            return (CaptureExposureMode)Device.exposureMode;
        }

        void GrabberEx::setExposureMode(CaptureExposureMode mode) {
            IfNullDevice();
            if(!isExposureModeSupported(mode)) {
                ofLogWarning("GrabberEx") << "setExposureMode: mode " << (int)mode << " is not supported.";
                return;
            }
            
            NSError *err = nil;
            if([Device lockForConfiguration:&err]) {
                Device.exposureMode = (AVCaptureExposureMode)mode;
            }
            
            [Device unlockForConfiguration];
            if(err) ofLogError("GrabberEx") << "error on setExposureMode: " << err.description.UTF8String;
        }

        bool GrabberEx::isExposureModeSupported(CaptureExposureMode mode) const {
            IfNullDevice(false);
            return [Device isExposureModeSupported:(AVCaptureExposureMode)mode];
        }

        CaptureWhiteBalanceMode GrabberEx::whiteBalanceMode() const {
            IfNullDevice((CaptureWhiteBalanceMode)0);
            return (CaptureWhiteBalanceMode)Device.whiteBalanceMode;
        }

        void GrabberEx::setWhiteBalanceMode(CaptureWhiteBalanceMode mode) {
            IfNullDevice();
            if(!isWhiteBalanceModeSupported(mode)) {
                ofLogWarning("GrabberEx") << "setWhiteBalanceMode: mode " << (int)mode << " is not supported.";
                return;
            }
            
            NSError *err = nil;
            if([Device lockForConfiguration:&err]) {
                Device.whiteBalanceMode = (AVCaptureWhiteBalanceMode)mode;
            }
            
            [Device unlockForConfiguration];
            if(err) ofLogError("GrabberEx") << "error on setWhiteBalanceMode: " << err.description.UTF8String;
        }

        bool GrabberEx::isWhiteBalanceModeSupported(CaptureWhiteBalanceMode mode) const {
            IfNullDevice(false);
            return [Device isWhiteBalanceModeSupported:(AVCaptureWhiteBalanceMode)mode];
        }

        bool GrabberEx::isAdjustingWhiteBalance() const {
            IfNullDevice(false);
            return Device.isAdjustingWhiteBalance;
        }

        CaptureFocusMode GrabberEx::focusMode() const {
            IfNullDevice((CaptureFocusMode)0);
            return (CaptureFocusMode)Device.focusMode;
        }

        bool GrabberEx::isFocusModeSupported(CaptureFocusMode mode) const {
            IfNullDevice(false);
            return [Device isFocusModeSupported:(AVCaptureFocusMode)mode];
        }

        ofVec2f GrabberEx::focusPointOfInterest() const {
            IfNullDevice({-1.0f, -1.0f});
            return ofVec2f(
                Device.focusPointOfInterest.x,
                Device.focusPointOfInterest.y
            );
        }

        void GrabberEx::setFocusPointOfInterest(ofVec2f focusPoint) {
            IfNullDevice();
            if(!isFocusPointOfInterestSupported()) {
                ofLogWarning("GrabberEx") << "setFocusPointOfInterest is not supported.";
                return;
            }
            
            NSError *err = nil;
            if([Device lockForConfiguration:&err]) {
                Device.focusPointOfInterest = CGPointMake(focusPoint.x, focusPoint.y);
            }
            
            [Device unlockForConfiguration];
            if(err) ofLogError("GrabberEx") << "error on setFocusPointOfInterest: " << err.description.UTF8String;
        }

        bool GrabberEx::isFocusPointOfInterestSupported() const {
            IfNullDevice(false);
            return Device.isFocusPointOfInterestSupported;
        }

        bool GrabberEx::isAdjustingFocus() const {
            IfNullDevice(false);
            return Device.isAdjustingFocus;
        }

        #undef IfNullDevice
        #undef Device
    };
};
