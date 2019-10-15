/*
 *  ofxAVFoundationGrabberEx.h
 */

#pragma once
#include "ofConstants.h"

//------
#include "ofVideoBaseTypes.h"
#include "ofPixels.h"
#include "ofTexture.h"
#include "ofThread.h"
#include "ofVec2f.h"
#include <mutex>

enum class CaptureExposureMode : std::uint8_t {
    Locked = 0,
    Auto,
    ContinuousAuto
};

enum class CaptureWhiteBalanceMode : std::uint8_t {
    Locked = 0,
    Auto,
    ContinuousAuto
};

enum class CaptureFocusMode : std::uint8_t {
    Locked = 0,
    Auto,
    ContinuousAuto
};

enum class CaptureDeviceTransportControlsPlaybackMode : std::uint8_t {
    NotPlayingMode = 0,
    PlayingMode
};
    
class ofxAVFoundationGrabberEx : virtual public ofBaseVideoGrabber{
public:
    ofxAVFoundationGrabberEx();
    ~ofxAVFoundationGrabberEx();

    void setDeviceID(int deviceID);
    void setDeviceUniqueID(const std::string &uniqueID);
    void setDesiredFrameRate(int capRate);
    bool setPixelFormat(ofPixelFormat PixelFormat);

    bool setup(int w, int h);
    void update();
    bool isFrameNew() const;
    void close();

    ofPixels&		 		getPixels();
    const ofPixels&		    getPixels() const;

    float getWidth() const{
        return width;
    }
    float getHeight() const{
        return height;
    }

    bool isInitialized() const;

    void updatePixelsCB();
    std::vector <ofVideoDevice> listDevices() const;
    ofPixelFormat getPixelFormat() const;
    
    std::string getUniqueID() const;
    std::string getModelID() const;
    std::string getManufacturer() const;
    std::string getLocalizedName() const;
    
    bool adjustingExposure() const;
    CaptureExposureMode exposureMode() const;
    void setExposureMode(CaptureExposureMode mode);
    bool isExposureModeSupported(CaptureExposureMode mode) const;
    
    CaptureWhiteBalanceMode whiteBalanceMode() const;
    void setWhiteBalanceMode(CaptureWhiteBalanceMode mode);
    bool isWhiteBalanceModeSupported(CaptureWhiteBalanceMode mode) const;
    bool isAdjustingWhiteBalance() const;
    
    CaptureFocusMode focusMode() const;
    bool isFocusModeSupported(CaptureFocusMode mode) const;
    ofVec2f focusPointOfInterest() const;
    void setFocusPointOfInterest(ofVec2f focusPoint);
    bool isFocusPointOfInterestSupported() const;
    bool isAdjustingFocus() const;
    
    bool transportControlsSupported() const;
    CaptureDeviceTransportControlsPlaybackMode transportControlsPlaybackMode() const;
    float transportControlsSpeed() const;
    void setTransportControlsPlaybackSetting(CaptureDeviceTransportControlsPlaybackMode mode, float speed);
protected:
    bool newFrame = false;
    bool bHavePixelsChanged = false;
    void clear();
    int width, height;

    int device = 0;
    bool bIsInit = false;

    int fps  = -1;
    ofTexture tex;
    ofPixels pixels;

    void *grabber_;

public:
    ofPixelFormat pixelFormat;
    ofPixels pixelsTmp;
    bool bLock = false;
    std::mutex capMutex;
};
