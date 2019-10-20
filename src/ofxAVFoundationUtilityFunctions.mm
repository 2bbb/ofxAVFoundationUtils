//
//  ofxAVFoundationUtilityFunctions.mm
//
//  Created by 2bit on 2019/10/15.
//

#include "ofLog.h"

#import "ofxAVFoundationUtilityFunctions.h"
#import <AVFoundation/AVFoundation.h>

namespace ofx {
    namespace AVFoundationUtils {
        std::size_t getNumCameraDevices() {
            return [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count;
        }
        CameraDeviceInfo getCameraDeviceInfo(int deviceID) {
            NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            if(deviceID < 0) {
                ofLogWarning("ofxAVFoundationUtils::getUniqueIDFromDeviceID") << "deviceID " << deviceID << " is invalid.";
                return {};
            } else if(devices.count <= deviceID) {
                ofLogWarning("ofxAVFoundationUtils::getUniqueIDFromDeviceID") << "deviceID " << deviceID << " is out of range. current device num is " << devices.count;
                return {};
            } else {
                AVCaptureDevice *device = devices[deviceID];
                return {
                    { device.uniqueID.UTF8String },
                    { device.modelID.UTF8String },
                    { device.manufacturer.UTF8String },
                    { device.localizedName.UTF8String }
                };
            }
        }
        std::string getUniqueIDFromDeviceID(int deviceID) {
            NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            if(deviceID < 0) {
                ofLogWarning("ofxAVFoundationUtils::getUniqueIDFromDeviceID") << "deviceID " << deviceID << " is invalid.";
                return "";
            } else if(devices.count <= deviceID) {
                ofLogWarning("ofxAVFoundationUtils::getUniqueIDFromDeviceID") << "deviceID " << deviceID << " is out of range. current device num is " << devices.count;
                return "";
            } else {
                return { devices[deviceID].uniqueID.UTF8String };
            }
        }
        int getDeviceIDFromUniqueID(const std::string &uniqueID) {
            NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            int i = 0;
            NSString *uid = [NSString stringWithUTF8String:uniqueID.c_str()];
            for(AVCaptureDevice *device in devices) {
                if([device.uniqueID isEqualToString:uid]) {
                    return i;
                }
                i++;
            }
            
            ofLogWarning("ofxAVFoundationUtils::getDeviceIDFromUniqueID") << "uniqueID " << uniqueID << " is out of range. current device num is " << devices.count;
            return -1;
        }
    };
};
