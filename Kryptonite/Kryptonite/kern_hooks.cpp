//
//  kern_hooks.cpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#include "kern_hooks.hpp"
#include "kern_nvramargs.hpp"
#include <Headers/kern_api.hpp>
#include <IOKit/IOService.h>
#include <libkern/c++/OSBoolean.h>

static constexpr const char *kHookModuleName = "hooks";

FunctionHooks::tIntelFBClientDoAttribute FunctionHooks::orgIntelFBClientDoAttribute = nullptr;
FunctionHooks::tIntelFramebufferGetOnlineInfo FunctionHooks::orgIntelFramebufferGetOnlineInfo = nullptr;
FunctionHooks::tAMD9500FindProjectByPartNumber FunctionHooks::orgAMD9500FindProjectByPartNumber = nullptr;
FunctionHooks::tAMDSupportTestVRAM FunctionHooks::orgAMDSupportTestVRAM = nullptr;
FunctionHooks::tAMDRadeonPopulateAccelConfig FunctionHooks::orgAMDRadeonPopulateAccelConfig = nullptr;
FunctionHooks::tAMDAccelSharedUserClientGetTargetAndMethodForIndex FunctionHooks::orgAMDAccelSharedUserClientGetTargetAndMethodForIndex = nullptr;
FunctionHooks::tIOAccelSharedUserClientGetTargetAndMethodForIndex FunctionHooks::orgIOAccelSharedUserClientGetTargetAndMethodForIndex = nullptr;
FunctionHooks::tAtiDeviceControlNotifyLinkChange FunctionHooks::orgAtiDeviceControlNotifyLinkChange = nullptr;
FunctionHooks::tAMDFramebufferValidateDetailedTiming FunctionHooks::orgAMDFramebufferValidateDetailedTiming = nullptr;
FunctionHooks::tAMDBaffinCapabilityMask FunctionHooks::orgAMDBaffinGetPixelEncodingCapabilities = nullptr;
FunctionHooks::tAMDBaffinCapabilityMask FunctionHooks::orgAMDBaffinGetBitDepthCapabilities = nullptr;
FunctionHooks::tAMDBaffinCapabilityMask FunctionHooks::orgAMDBaffinGetColorimetryCapabilities = nullptr;
FunctionHooks::tAMDBaffinCapabilityMask FunctionHooks::orgAMDBaffinGetDynamicRangeCapabilities = nullptr;

static IOExternalMethod gAMDSharedUserClientVariableOutputMethod {};
static bool gAMDSharedUserClientVariableOutputLogged = false;

static bool ensureBooleanProperty(IORegistryEntry *entry, const char *key, bool value) {
    if (entry == nullptr || key == nullptr) {
        return false;
    }

    auto desired = value ? kOSBooleanTrue : kOSBooleanFalse;
    auto existing = OSDynamicCast(OSBoolean, entry->getProperty(key));
    if (existing == desired) {
        return false;
    }

    entry->setProperty(key, desired);
    return true;
}

static void primeAMDLoadProperties(IOService *service, const char *reason) {
    if (!NVRAMArgs::shouldEnableAMDAccelPrime()) {
        return;
    }

    if (service == nullptr) {
        return;
    }

    IOService *pciProvider = nullptr;
    bool changed = false;

    for (IOService *current = service; current != nullptr; current = current->getProvider()) {
        changed |= ensureBooleanProperty(current, "LoadAccelerator", true);
        changed |= ensureBooleanProperty(current, "LoadHWServices", true);

        // The IOPCIDevice provider is the personality match target for the
        // Polaris accelerator and HWServices personalities.
        if (current->getProperty("vendor-id") != nullptr && current->getProperty("device-id") != nullptr) {
            pciProvider = current;
            break;
        }
    }

    if (!changed || pciProvider == nullptr) {
        return;
    }

    SYSLOG(kHookModuleName, "Primed AMD load properties on %s via %s.", pciProvider->getName(), reason);
    pciProvider->registerService();
}

uint32_t FunctionHooks::forceLegacyAMDHdmiCapabilityMask(const char *capabilityName) {
    SYSLOG(moduleName, "Forcing legacy AMD HDMI capability mask for %s.", capabilityName);
    return 0;
}

int FunctionHooks::thunderboltShouldSkipEnumeration() {
    if (NVRAMArgs::skipThunderboltEnum()) {
        SYSLOG(moduleName, "Boot arg detected: skipping Thunderbolt enumeration.");
        return 1;
    }
    
    SYSLOG(moduleName, "Boot arg not present: proceeding with Thunderbolt enumeration.");
    return 0;
}

FunctionHooks::tIntelFBClientDoAttribute &FunctionHooks::intelFBClientDoAttributeOriginal() {
    return orgIntelFBClientDoAttribute;
}

FunctionHooks::tIntelFramebufferGetOnlineInfo &FunctionHooks::intelFramebufferGetOnlineInfoOriginal() {
    return orgIntelFramebufferGetOnlineInfo;
}

FunctionHooks::tAMD9500FindProjectByPartNumber &FunctionHooks::amd9500FindProjectByPartNumberOriginal() {
    return orgAMD9500FindProjectByPartNumber;
}

FunctionHooks::tAMDSupportTestVRAM &FunctionHooks::amdSupportTestVRAMOriginal() {
    return orgAMDSupportTestVRAM;
}

FunctionHooks::tAMDRadeonPopulateAccelConfig &FunctionHooks::amdRadeonPopulateAccelConfigOriginal() {
    return orgAMDRadeonPopulateAccelConfig;
}

FunctionHooks::tAMDAccelSharedUserClientGetTargetAndMethodForIndex &FunctionHooks::amdAccelSharedUserClientGetTargetAndMethodForIndexOriginal() {
    return orgAMDAccelSharedUserClientGetTargetAndMethodForIndex;
}

FunctionHooks::tIOAccelSharedUserClientGetTargetAndMethodForIndex &FunctionHooks::ioAccelSharedUserClientGetTargetAndMethodForIndexOriginal() {
    return orgIOAccelSharedUserClientGetTargetAndMethodForIndex;
}

FunctionHooks::tAtiDeviceControlNotifyLinkChange &FunctionHooks::atiDeviceControlNotifyLinkChangeOriginal() {
    return orgAtiDeviceControlNotifyLinkChange;
}

FunctionHooks::tAMDFramebufferValidateDetailedTiming &FunctionHooks::amdFramebufferValidateDetailedTimingOriginal() {
    return orgAMDFramebufferValidateDetailedTiming;
}

FunctionHooks::tAMDBaffinCapabilityMask &FunctionHooks::amdBaffinGetPixelEncodingCapabilitiesOriginal() {
    return orgAMDBaffinGetPixelEncodingCapabilities;
}

FunctionHooks::tAMDBaffinCapabilityMask &FunctionHooks::amdBaffinGetBitDepthCapabilitiesOriginal() {
    return orgAMDBaffinGetBitDepthCapabilities;
}

FunctionHooks::tAMDBaffinCapabilityMask &FunctionHooks::amdBaffinGetColorimetryCapabilitiesOriginal() {
    return orgAMDBaffinGetColorimetryCapabilities;
}

FunctionHooks::tAMDBaffinCapabilityMask &FunctionHooks::amdBaffinGetDynamicRangeCapabilitiesOriginal() {
    return orgAMDBaffinGetDynamicRangeCapabilities;
}

IOReturn FunctionHooks::intelFBClientDoAttribute(void *fbclient, uint32_t attribute, unsigned long *unk1, unsigned long unk2, unsigned long *unk3, unsigned long *unk4, void *externalMethodArguments) {
    if (attribute == kAGDCRegisterCallback) {
        SYSLOG(moduleName, "Blocking Intel framebuffer AGDC registration callback.");
        return kIOReturnUnsupported;
    }

    if (!orgIntelFBClientDoAttribute) {
        SYSLOG(moduleName, "Original Intel framebuffer doAttribute callback missing.");
        return kIOReturnUnsupported;
    }

    return orgIntelFBClientDoAttribute(fbclient, attribute, unk1, unk2, unk3, unk4, externalMethodArguments);
}

IOReturn FunctionHooks::intelFramebufferGetOnlineInfo(IORegistryEntry *framebuffer, uint8_t *displayConnected, uint8_t *edid, void *displayPortType, bool *linkState, bool forceHotPlugDetect) {
    IOReturn ret = kIOReturnSuccess;
    if (orgIntelFramebufferGetOnlineInfo) {
        ret = orgIntelFramebufferGetOnlineInfo(framebuffer, displayConnected, edid, displayPortType, linkState, forceHotPlugDetect);
    }

    if (displayConnected != nullptr && *displayConnected == 0) {
        SYSLOG(moduleName, "Forcing Intel framebuffer online info to connected.");
        *displayConnected = 1;
    }

    return ret;
}

IOReturn FunctionHooks::amd9500FindProjectByPartNumber(IOService *controller, void *properties) {
    primeAMDLoadProperties(controller, "findProjectByPartNumber");
    SYSLOG(moduleName, "Bypassing AMD9500Controller project selection by part number.");
    return kIOReturnNotFound;
}

bool FunctionHooks::amdSupportTestVRAM(void *controller, uint32_t reg, bool retryOnFail) {
    primeAMDLoadProperties(static_cast<IOService *>(controller), "TestVRAM");
    SYSLOG(moduleName, "Skipping AMD VRAM self-test on reg %u.", reg);
    return true;
}

void FunctionHooks::setAMDAccelGVAProperties(IOService *accelService) {
    if (accelService == nullptr) {
        return;
    }

    auto codecString = OSDynamicCast(OSString, accelService->getProperty("IOGVACodec"));
    if (codecString == nullptr) {
        SYSLOG(moduleName, "Setting IOGVACodec to VCE on AMD accelerator.");
        accelService->setProperty("IOGVACodec", "VCE");
        return;
    }

    auto codec = codecString->getCStringNoCopy();
    if (codec == nullptr || strncmp(codec, "AMD", strlen("AMD")) != 0) {
        return;
    }

    if (accelService->getProperty("IOGVAHEVCDecode") == nullptr) {
        auto decodeFlag = OSString::withCString("1");
        if (decodeFlag != nullptr) {
            SYSLOG(moduleName, "Recovering IOGVAHEVCDecode on AMD accelerator.");
            accelService->setProperty("IOGVAHEVCDecode", decodeFlag);
            decodeFlag->release();
        }
    }

    if (accelService->getProperty("IOGVAHEVCEncode") == nullptr) {
        auto encodeFlag = OSString::withCString("1");
        if (encodeFlag != nullptr) {
            SYSLOG(moduleName, "Recovering IOGVAHEVCEncode on AMD accelerator.");
            accelService->setProperty("IOGVAHEVCEncode", encodeFlag);
            encodeFlag->release();
        }
    }
}

void FunctionHooks::amdRadeonPopulateAccelConfig(IOService *accelService, void *accelConfig) {
    if (orgAMDRadeonPopulateAccelConfig != nullptr) {
        orgAMDRadeonPopulateAccelConfig(accelService, accelConfig);
    } else {
        SYSLOG(moduleName, "Original AMD populateAccelConfig callback missing.");
    }

    setAMDAccelGVAProperties(accelService);
}

IOExternalMethod *FunctionHooks::amdAccelSharedUserClientGetTargetAndMethodForIndex(void *userClient, IOService **targetP, uint32_t index) {
    if (orgAMDAccelSharedUserClientGetTargetAndMethodForIndex == nullptr) {
        SYSLOG(moduleName, "Original AMD shared user-client method resolver missing.");
        return nullptr;
    }

    auto method = orgAMDAccelSharedUserClientGetTargetAndMethodForIndex(userClient, targetP, index);
    if (method == nullptr) {
        return nullptr;
    }

    const bool matchesObservedSelector = index == kAMDSharedUserClientVariableOutputSelector;
    const bool matchesNormalizedSelector = index == kAMDSharedUserClientVariableOutputNormalizedSelector;
    if (!matchesObservedSelector && !matchesNormalizedSelector) {
        return method;
    }

    auto type = static_cast<uint32_t>(method->flags & kIOUCTypeMask);
    if (!gAMDSharedUserClientVariableOutputLogged) {
        SYSLOG(moduleName,
               "AMD shared user-client selector %u flags=0x%x count0=0x%llx count1=0x%llx.",
               index,
               method->flags,
               static_cast<unsigned long long>(method->count0),
               static_cast<unsigned long long>(method->count1));
        gAMDSharedUserClientVariableOutputLogged = true;
    }

    if (type != kIOUCScalarIStructO && type != kIOUCStructIStructO) {
        return method;
    }

    if (method->count1 == kIOUCVariableStructureSize) {
        return method;
    }

    gAMDSharedUserClientVariableOutputMethod = *method;
    gAMDSharedUserClientVariableOutputMethod.count1 = kIOUCVariableStructureSize;

    SYSLOG(moduleName,
           "Relaxing AMD shared user-client selector %u%s output size check from 0x%llx to variable.",
           index,
           matchesNormalizedSelector ? " (normalized from shared shim selector)" : "",
           static_cast<unsigned long long>(method->count1));
    return &gAMDSharedUserClientVariableOutputMethod;
}

IOExternalMethod *FunctionHooks::ioAccelSharedUserClientGetTargetAndMethodForIndex(void *userClient, IOService **targetP, uint32_t index) {
    if (orgIOAccelSharedUserClientGetTargetAndMethodForIndex == nullptr) {
        SYSLOG(moduleName, "Original IOAccel shared user-client method resolver missing.");
        return nullptr;
    }

    auto method = orgIOAccelSharedUserClientGetTargetAndMethodForIndex(userClient, targetP, index);
    if (method == nullptr) {
        return nullptr;
    }

    const bool matchesObservedSelector = index == kAMDSharedUserClientVariableOutputSelector;
    const bool matchesNormalizedSelector = index == kAMDSharedUserClientVariableOutputNormalizedSelector;
    if (!matchesObservedSelector && !matchesNormalizedSelector) {
        return method;
    }

    auto type = static_cast<uint32_t>(method->flags & kIOUCTypeMask);
    SYSLOG(moduleName,
           "IOAccel shared user-client selector %u flags=0x%x count0=0x%llx count1=0x%llx.",
           index,
           method->flags,
           static_cast<unsigned long long>(method->count0),
           static_cast<unsigned long long>(method->count1));

    if (type != kIOUCScalarIStructO && type != kIOUCStructIStructO) {
        return method;
    }

    if (method->count1 == kIOUCVariableStructureSize) {
        return method;
    }

    gAMDSharedUserClientVariableOutputMethod = *method;
    gAMDSharedUserClientVariableOutputMethod.count1 = kIOUCVariableStructureSize;

    SYSLOG(moduleName,
           "Relaxing IOAccel shared user-client selector %u%s output size check from 0x%llx to variable.",
           index,
           matchesNormalizedSelector ? " (normalized shared selector)" : "",
           static_cast<unsigned long long>(method->count1));
    return &gAMDSharedUserClientVariableOutputMethod;
}

bool FunctionHooks::atiDeviceControlNotifyLinkChange(void *atiDeviceControl, uint32_t event, void *eventData, uint32_t eventFlags) {
    bool ret = false;
    if (orgAtiDeviceControlNotifyLinkChange) {
        ret = orgAtiDeviceControlNotifyLinkChange(atiDeviceControl, event, eventData, eventFlags);
    } else {
        SYSLOG(moduleName, "Original AMD notifyLinkChange callback missing.");
    }

    if (event == 1 || event == 2 || event == 0x5b || event == 0x5d) {
        primeAMDLoadProperties(static_cast<IOService *>(atiDeviceControl), "notifyLinkChange");
    }

    if (event == kAGDCValidateDetailedTiming && eventData != nullptr) {
        auto cmd = static_cast<AGDCValidateDetailedTiming *>(eventData);
        SYSLOG(moduleName, "AMD detailed timing validation framebuffer=%u ret=%d modeStatus=%u.", cmd->framebufferIndex, ret, cmd->modeStatus);
        if (!ret || cmd->modeStatus < 1 || cmd->modeStatus > 3) {
            SYSLOG(moduleName, "Normalising AMD detailed timing validation for framebuffer %u.", cmd->framebufferIndex);
            cmd->modeStatus = 2;
            ret = true;
        }
    }

    return ret;
}

IOReturn FunctionHooks::amdFramebufferValidateDetailedTiming(void *framebuffer, void *timingData, uint64_t payloadSize) {
    IOReturn ret = kIOReturnSuccess;
    if (orgAMDFramebufferValidateDetailedTiming != nullptr) {
        ret = orgAMDFramebufferValidateDetailedTiming(framebuffer, timingData, payloadSize);
    } else {
        SYSLOG(moduleName, "Original AMDFramebuffer validateDetailedTiming callback missing.");
        return kIOReturnSuccess;
    }

    if (payloadSize == 0xCC && (ret == kAMDTimingValidationFailure || ret == kAMDTimingUnsupportedFailure)) {
        SYSLOG(moduleName, "Relaxing AMDFramebuffer validateDetailedTiming failure 0x%x for payload size 0x%llx.", ret, payloadSize);
        return kIOReturnSuccess;
    }

    return ret;
}

uint32_t FunctionHooks::amdBaffinGetPixelEncodingCapabilities(void *controller) {
    (void)controller;
    return forceLegacyAMDHdmiCapabilityMask("pixel encoding");
}

uint32_t FunctionHooks::amdBaffinGetBitDepthCapabilities(void *controller) {
    (void)controller;
    return forceLegacyAMDHdmiCapabilityMask("bit depth");
}

uint32_t FunctionHooks::amdBaffinGetColorimetryCapabilities(void *controller) {
    (void)controller;
    return forceLegacyAMDHdmiCapabilityMask("colorimetry");
}

uint32_t FunctionHooks::amdBaffinGetDynamicRangeCapabilities(void *controller) {
    (void)controller;
    return forceLegacyAMDHdmiCapabilityMask("dynamic range");
}
