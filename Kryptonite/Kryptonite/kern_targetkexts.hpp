//
//  kern_targetkexts.hpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#ifndef kern_targetkexts_hpp
#define kern_targetkexts_hpp

template <typename T,unsigned S>
inline unsigned arraysize(const T (&v)[S]) { return S; }

static const char* targetKexts[] = {
    "/System/Library/Extensions/AppleGraphicsControl.kext/Contents/PlugIns/AppleGPUWrangler.kext/Contents/MacOS/AppleGPUWrangler",
    "/System/Library/Extensions/IOGraphicsFamily.kext/IOGraphicsFamily",
    "/System/Library/Extensions/AppleGraphicsControl.kext/Contents/PlugIns/AppleMuxControl.kext/Contents/MacOS/AppleMuxControl",
    "/System/Library/Extensions/IOThunderboltFamily.kext/Contents/MacOS/IOThunderboltFamily",
    "/System/Library/Extensions/IOPCIFamily.kext/IOPCIFamily",
    "/System/Library/Extensions/AMDRadeonX4000.kext/Contents/MacOS/AMDRadeonX4000",
    "/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/MacOS/AMDRadeonX4000HWServices",
    "/System/Library/Extensions/AMD9500Controller.kext/Contents/MacOS/AMD9500Controller",
    "/System/Library/Extensions/AMDFramebuffer.kext/Contents/MacOS/AMDFramebuffer"
};

static const char* iopcifamilyKextPaths[] = {
    "/System/Library/Extensions/IOPCIFamily.kext/IOPCIFamily",
    "/System/Library/Extensions/IOPCIFamily.kext/Contents/MacOS/IOPCIFamily"
};

static KernelPatcher::KextInfo kextList[] {
    {"com.apple.AppleGPUWrangler", &targetKexts[0], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.iokit.IOGraphicsFamily", &targetKexts[1], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.driver.AppleMuxControl", &targetKexts[2], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.iokit.IOThunderboltFamily", &targetKexts[3], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.iokit.IOPCIFamily", &iopcifamilyKextPaths[0], arraysize(iopcifamilyKextPaths), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMDRadeonX4000", &targetKexts[5], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMDRadeonX4000HWServices", &targetKexts[6], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMD9500Controller", &targetKexts[7], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded},
    {"com.apple.kext.AMDFramebuffer", &targetKexts[8], arraysize(targetKexts), {true}, {}, KernelPatcher::KextInfo::Unloaded}
};

static size_t kextListSize = arraysize(kextList);

#endif /* kern_targetkexts_hpp */
