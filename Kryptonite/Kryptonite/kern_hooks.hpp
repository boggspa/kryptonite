//
//  kern_hooks.hpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#ifndef kern_hooks_hpp
#define kern_hooks_hpp

#include <Headers/kern_iokit.hpp>
#include <IOKit/IOUserClient.h>
#include <libkern/c++/OSArray.h>
#include <libkern/c++/OSDictionary.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSString.h>

class IOService;

class FunctionHooks {
private:
    constexpr static const char* moduleName = "hooks";
    constexpr static uint32_t kAGDCRegisterCallback = 0x923;
    constexpr static uint32_t kAGDCValidateDetailedTiming = 10;
    constexpr static uint32_t kAMDSharedUserClientVariableOutputSelector = 6003;
    constexpr static uint32_t kAMDSharedUserClientVariableOutputNormalizedSelector = 2;
    constexpr static IOReturn kAMDTimingValidationFailure = static_cast<IOReturn>(0xe00002bc);
    constexpr static IOReturn kAMDTimingUnsupportedFailure = static_cast<IOReturn>(0xe00002c7);

#pragma pack(push, 1)
    struct AGDCDetailedTimingInformation {
        uint32_t horizontalScaledInset;
        uint32_t verticalScaledInset;
        uint32_t scalerFlags;
        uint32_t horizontalScaled;
        uint32_t verticalScaled;
        uint32_t signalConfig;
        uint32_t signalLevels;
        uint64_t pixelClock;
        uint64_t minPixelClock;
        uint64_t maxPixelClock;
        uint32_t horizontalActive;
        uint32_t horizontalBlanking;
        uint32_t horizontalSyncOffset;
        uint32_t horizontalSyncPulseWidth;
        uint32_t verticalActive;
        uint32_t verticalBlanking;
        uint32_t verticalSyncOffset;
        uint32_t verticalSyncPulseWidth;
        uint32_t horizontalBorderLeft;
        uint32_t horizontalBorderRight;
        uint32_t verticalBorderTop;
        uint32_t verticalBorderBottom;
        uint32_t horizontalSyncConfig;
        uint32_t horizontalSyncLevel;
        uint32_t verticalSyncConfig;
        uint32_t verticalSyncLevel;
        uint32_t numLinks;
        uint32_t verticalBlankingExtension;
        uint16_t pixelEncoding;
        uint16_t bitsPerColorComponent;
        uint16_t colorimetry;
        uint16_t dynamicRange;
        uint16_t dscCompressedBitsPerPixel;
        uint16_t dscSliceHeight;
        uint16_t dscSliceWidth;
    };

    struct AGDCValidateDetailedTiming {
        uint32_t framebufferIndex;
        AGDCDetailedTimingInformation timing;
        uint16_t padding1[5];
        void *cfgInfo;
        int32_t frequency;
        uint16_t padding2[6];
        uint32_t modeStatus;
        uint16_t padding3[2];
    };
#pragma pack(pop)

    using tIntelFBClientDoAttribute = IOReturn (*)(void *, uint32_t, unsigned long *, unsigned long, unsigned long *, unsigned long *, void *);
    using tIntelFramebufferGetOnlineInfo = IOReturn (*)(IORegistryEntry *, uint8_t *, uint8_t *, void *, bool *, bool);
    using tAMD9500FindProjectByPartNumber = IOReturn (*)(IOService *, void *);
    using tAMDSupportTestVRAM = bool (*)(void *, uint32_t, bool);
    using tAMDRadeonPopulateAccelConfig = void (*)(IOService *, void *);
    using tAMDAccelSharedUserClientGetTargetAndMethodForIndex = IOExternalMethod *(*)(void *, IOService **, uint32_t);
    using tIOAccelSharedUserClientGetTargetAndMethodForIndex = IOExternalMethod *(*)(void *, IOService **, uint32_t);
    using tAtiDeviceControlNotifyLinkChange = bool (*)(void *, uint32_t, void *, uint32_t);
    using tAMDFramebufferValidateDetailedTiming = IOReturn (*)(void *, void *, uint64_t);
    using tAMDBaffinCapabilityMask = uint32_t (*)(void *);
    static tIntelFBClientDoAttribute orgIntelFBClientDoAttribute;
    static tIntelFramebufferGetOnlineInfo orgIntelFramebufferGetOnlineInfo;
    static tAMD9500FindProjectByPartNumber orgAMD9500FindProjectByPartNumber;
    static tAMDSupportTestVRAM orgAMDSupportTestVRAM;
    static tAMDRadeonPopulateAccelConfig orgAMDRadeonPopulateAccelConfig;
    static tAMDAccelSharedUserClientGetTargetAndMethodForIndex orgAMDAccelSharedUserClientGetTargetAndMethodForIndex;
    static tIOAccelSharedUserClientGetTargetAndMethodForIndex orgIOAccelSharedUserClientGetTargetAndMethodForIndex;
    static tAtiDeviceControlNotifyLinkChange orgAtiDeviceControlNotifyLinkChange;
    static tAMDFramebufferValidateDetailedTiming orgAMDFramebufferValidateDetailedTiming;
    static tAMDBaffinCapabilityMask orgAMDBaffinGetPixelEncodingCapabilities;
    static tAMDBaffinCapabilityMask orgAMDBaffinGetBitDepthCapabilities;
    static tAMDBaffinCapabilityMask orgAMDBaffinGetColorimetryCapabilities;
    static tAMDBaffinCapabilityMask orgAMDBaffinGetDynamicRangeCapabilities;

    static void setAMDAccelGVAProperties(IOService *accelService);
    static uint32_t forceLegacyAMDHdmiCapabilityMask(const char *capabilityName);
    
public:
    static int thunderboltShouldSkipEnumeration();
    static tIntelFBClientDoAttribute &intelFBClientDoAttributeOriginal();
    static tIntelFramebufferGetOnlineInfo &intelFramebufferGetOnlineInfoOriginal();
    static tAMD9500FindProjectByPartNumber &amd9500FindProjectByPartNumberOriginal();
    static tAMDSupportTestVRAM &amdSupportTestVRAMOriginal();
    static tAMDRadeonPopulateAccelConfig &amdRadeonPopulateAccelConfigOriginal();
    static tAMDAccelSharedUserClientGetTargetAndMethodForIndex &amdAccelSharedUserClientGetTargetAndMethodForIndexOriginal();
    static tIOAccelSharedUserClientGetTargetAndMethodForIndex &ioAccelSharedUserClientGetTargetAndMethodForIndexOriginal();
    static tAtiDeviceControlNotifyLinkChange &atiDeviceControlNotifyLinkChangeOriginal();
    static tAMDFramebufferValidateDetailedTiming &amdFramebufferValidateDetailedTimingOriginal();
    static tAMDBaffinCapabilityMask &amdBaffinGetPixelEncodingCapabilitiesOriginal();
    static tAMDBaffinCapabilityMask &amdBaffinGetBitDepthCapabilitiesOriginal();
    static tAMDBaffinCapabilityMask &amdBaffinGetColorimetryCapabilitiesOriginal();
    static tAMDBaffinCapabilityMask &amdBaffinGetDynamicRangeCapabilitiesOriginal();
    static IOReturn intelFBClientDoAttribute(void *fbclient, uint32_t attribute, unsigned long *unk1, unsigned long unk2, unsigned long *unk3, unsigned long *unk4, void *externalMethodArguments);
    static IOReturn intelFramebufferGetOnlineInfo(IORegistryEntry *framebuffer, uint8_t *displayConnected, uint8_t *edid, void *displayPortType, bool *linkState, bool forceHotPlugDetect);
    static IOReturn amd9500FindProjectByPartNumber(IOService *controller, void *properties);
    static bool amdSupportTestVRAM(void *controller, uint32_t reg, bool retryOnFail);
    static void amdRadeonPopulateAccelConfig(IOService *accelService, void *accelConfig);
    static IOExternalMethod *amdAccelSharedUserClientGetTargetAndMethodForIndex(void *userClient, IOService **targetP, uint32_t index);
    static IOExternalMethod *ioAccelSharedUserClientGetTargetAndMethodForIndex(void *userClient, IOService **targetP, uint32_t index);
    static bool atiDeviceControlNotifyLinkChange(void *atiDeviceControl, uint32_t event, void *eventData, uint32_t eventFlags);
    static IOReturn amdFramebufferValidateDetailedTiming(void *framebuffer, void *timingData, uint64_t payloadSize);
    static uint32_t amdBaffinGetPixelEncodingCapabilities(void *controller);
    static uint32_t amdBaffinGetBitDepthCapabilities(void *controller);
    static uint32_t amdBaffinGetColorimetryCapabilities(void *controller);
    static uint32_t amdBaffinGetDynamicRangeCapabilities(void *controller);
    
};

#endif /* kern_hooks_hpp */
