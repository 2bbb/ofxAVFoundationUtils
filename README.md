# ofxAVFoundationGrabberEx

extended ofAVFoundationGrabber forked from core ofAVFoundationGrabber and add some features.

* get unique id and other info
* set exposure, white balance, focus mode if device corresponds to.

## how to use

```cpp
class ofApp : public ofBaseApp {
    ofVideoGrabber grabber;
    std::shared_ptr<ofxAVFoundationGrabberEx> raw_grabber;
public:
    void setup() override {
        raw_grabber = std::make_shared<ofxAVFoundationGrabberEx>();
        grabber.setGrabber(raw_grabber);
        raw_grabber->setDeviceUniqueID("0x14220000046d081b");
        grabber.setup(1280, 720);
        raw_grabber->setExposureMode(CaptureExposureMode::Locked);
        std::string uniqueID = raw_grabber->getUniqueID();
        ...
    }
    ...
}
```

## License

MIT License.

## Author

- ISHII 2bit [ISHII Tsuubito Program Office]
- i[at]2bit.jp