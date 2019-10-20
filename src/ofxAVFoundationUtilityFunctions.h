//
//  ofxAVFoundationUtilityFunctions.h
//
//  Created by 2bit on 2019/10/15.
//

#pragma once

#include <string>

namespace ofx {
    namespace AVFoundationUtils {
        struct CameraDeviceInfo {
            std::string uniqueID;
            std::string modelID;
            std::string manufacturer;
            std::string localizedName;
        };
        std::size_t getNumCameraDevices();
        CameraDeviceInfo getCameraDeviceInfo(int deviceID);
        std::string getUniqueIDFromDeviceID(int deviceID);
        int getDeviceIDFromUniqueID(const std::string &uniqueID);
    };
};
