//
//  kern_patches.cpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/4/21.
//

#include "kern_patches.hpp"
#include "kern_nvramargs.hpp"
#include "kern_patchapplicator.hpp"
#include "kern_compatibility.hpp"
#include "kern_hooks.hpp"

static PatchApplicator patchApplicator;
static constexpr const char *amdBitsPerComponentSymbol = "__ZL18BITS_PER_COMPONENT";

static bool shouldSkipPatch(const char *patchName, bool skipToggle) {
    if (NVRAMArgs::isProbeMode()) {
        SYSLOG("patches", "Probe mode enabled, skipping %s.", patchName);
        return true;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG("patches", "Global skip enabled, skipping %s.", patchName);
        return true;
    }

    if (skipToggle) {
        SYSLOG("patches", "Patch toggle disabled %s.", patchName);
        return true;
    }

    return false;
}

static bool shouldSkipAMDCompatibilityPatch(const char *patchName) {
    if (!NVRAMArgs::isAMD()) {
        return true;
    }

    if (!NVRAMArgs::shouldEnableAMDCompatibilityPatch()) {
        return true;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG("patches", "Probe mode enabled, skipping %s.", patchName);
        return true;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG("patches", "Global skip enabled, skipping %s.", patchName);
        return true;
    }

    return false;
}

void Patches::init() {
    NVRAMArgs::init();
}

void Patches::unblockLegacyThunderbolt(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (shouldSkipPatch("unblockLegacyThunderbolt", NVRAMArgs::shouldSkipAGDCPatch())) {
        return;
    }
    
    KernelPatcher::LookupPatch patch;
    uint8_t tbMinType = 0x03;
    if (NVRAMArgs::isThunderbolt1()) {
        tbMinType = 0x01;
    } else if (NVRAMArgs::isThunderbolt2()) {
        tbMinType = 0x02;
    }
    
    if (Compatibility::isOlderKernel()) {
        uint8_t tbSwitchTypeChar = 0x33;
        if (NVRAMArgs::isThunderbolt1()) {
            tbSwitchTypeChar = 0x31;
        } else if (NVRAMArgs::isThunderbolt2()) {
            tbSwitchTypeChar = 0x32;
        }
        const uint8_t find[] = {0x49, 0x4f, 0x54, 0x68, 0x75, 0x6e, 0x64, 0x65, 0x72, 0x62, 0x6f, 0x6c, 0x74, 0x53, 0x77, 0x69, 0x74, 0x63, 0x68, 0x54, 0x79, 0x70, 0x65, 0x33};
        const uint8_t repl[] = {0x49, 0x4f, 0x54, 0x68, 0x75, 0x6e, 0x64, 0x65, 0x72, 0x62, 0x6f, 0x6c, 0x74, 0x53, 0x77, 0x69, 0x74, 0x63, 0x68, 0x54, 0x79, 0x70, 0x65, tbSwitchTypeChar};
        patch = {kext, find, repl, sizeof(find), 1};
    } else if (getKernelVersion() == KernelVersion::Sequoia) {
        // Sequoia 15.x: tighten to full instruction window and patch TB type threshold
        // cmpq $0x3,%rax ; jb +0x0a ; movq (%r14),%rax ; movb $0x1,0x178(%rax)
        const uint8_t find[] = {0x48, 0x83, 0xf8, 0x03, 0x72, 0x0a, 0x49, 0x8b, 0x06, 0xc6, 0x80, 0x78, 0x01, 0x00, 0x00, 0x01};
        const uint8_t repl[] = {0x48, 0x83, 0xf8, tbMinType, 0x72, 0x0a, 0x49, 0x8b, 0x06, 0xc6, 0x80, 0x78, 0x01, 0x00, 0x00, 0x01};
        SYSLOG(moduleName, "Sequoia AGDC threshold patch using krytbtv=%u.", tbMinType);
        patch = {kext, find, repl, sizeof(find), 1};
    } else {
        const uint8_t find[] = {0xf8, 0x03, 0x0f, 0x82, 0x78, 0xff, 0xff, 0xff, 0x49, 0x8b, 0x06, 0xc6, 0x80, 0x78, 0x01, 0x00};
        const uint8_t repl[] = {0xf8, 0x00, 0x0f, 0x82, 0x78, 0xff, 0xff, 0xff, 0x49, 0x8b, 0x06, 0xc6, 0x80, 0x78, 0x01, 0x00};
        patch = {kext, find, repl, sizeof(find), 1};
    }
    patchApplicator.applyLookupPatch(patcher, &patch, "unblockLegacyThunderbolt");
}

void Patches::disableIntelFramebufferAGDC(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (!NVRAMArgs::shouldEnableIntelAGDCDisabler()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping disableIntelFramebufferAGDC.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping disableIntelFramebufferAGDC.");
        return;
    }

    KernelPatcher::RouteRequest vendorRequest(
        "__ZN20IntelFBClientControl24vendor_doDeviceAttributeEjPmmS0_S0_P25IOExternalMethodArguments",
        FunctionHooks::intelFBClientDoAttribute,
        FunctionHooks::intelFBClientDoAttributeOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &vendorRequest, address, size, "disableIntelFramebufferAGDC-vendor");
    if (vendorRequest.from != 0 && FunctionHooks::intelFBClientDoAttributeOriginal() != nullptr) {
        return;
    }

    patcher.clearError();

    KernelPatcher::RouteRequest legacyRequest(
        "__ZN20IntelFBClientControl11doAttributeEjPmmS0_S0_P25IOExternalMethodArguments",
        FunctionHooks::intelFBClientDoAttribute,
        FunctionHooks::intelFBClientDoAttributeOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &legacyRequest, address, size, "disableIntelFramebufferAGDC-legacy");
}

void Patches::forceIntelFramebufferOnlineDisplays(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (!NVRAMArgs::shouldEnableIntelForceOnline()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping forceIntelFramebufferOnlineDisplays.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping forceIntelFramebufferOnlineDisplays.");
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN21AppleIntelFramebuffer13GetOnlineInfoEPhS0_PNS_15DisplayPortTypeEPbb",
        FunctionHooks::intelFramebufferGetOnlineInfo,
        FunctionHooks::intelFramebufferGetOnlineInfoOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "forceIntelFramebufferOnlineDisplays");
}

void Patches::bypassAMDProjectSelection(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (shouldSkipAMDCompatibilityPatch("bypassAMDProjectSelection")) {
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN17AMD9500Controller23findProjectByPartNumberEP20ControllerProperties",
        FunctionHooks::amd9500FindProjectByPartNumber,
        FunctionHooks::amd9500FindProjectByPartNumberOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "bypassAMDProjectSelection");
}

void Patches::skipAMDVRAMTest(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (shouldSkipAMDCompatibilityPatch("skipAMDVRAMTest")) {
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN13ATIController8TestVRAME13PCI_REG_INDEXb",
        FunctionHooks::amdSupportTestVRAM,
        FunctionHooks::amdSupportTestVRAMOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "skipAMDVRAMTest");
}

void Patches::stabiliseAMDAccelConfig(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (shouldSkipAMDCompatibilityPatch("stabiliseAMDAccelConfig")) {
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN37AMDRadeonX4000_AMDGraphicsAccelerator19populateAccelConfigEP13IOAccelConfig",
        FunctionHooks::amdRadeonPopulateAccelConfig,
        FunctionHooks::amdRadeonPopulateAccelConfigOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "stabiliseAMDAccelConfig");
}

void Patches::relaxAMDSharedUserClientOutputSizing(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (!NVRAMArgs::shouldEnableAMDSharedUserClientVariableOutput()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping relaxAMDSharedUserClientOutputSizing.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping relaxAMDSharedUserClientOutputSizing.");
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN39AMDRadeonX4000_AMDAccelSharedUserClient26getTargetAndMethodForIndexEPP9IOServicej",
        FunctionHooks::amdAccelSharedUserClientGetTargetAndMethodForIndex,
        FunctionHooks::amdAccelSharedUserClientGetTargetAndMethodForIndexOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "relaxAMDSharedUserClientOutputSizing");
}

void Patches::relaxIOAccelSharedUserClientOutputSizing(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (!NVRAMArgs::shouldEnableAMDSharedUserClientVariableOutput()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping relaxIOAccelSharedUserClientOutputSizing.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping relaxIOAccelSharedUserClientOutputSizing.");
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN24IOAccelSharedUserClient226getTargetAndMethodForIndexEPP9IOServicej",
        FunctionHooks::ioAccelSharedUserClientGetTargetAndMethodForIndex,
        FunctionHooks::ioAccelSharedUserClientGetTargetAndMethodForIndexOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "relaxIOAccelSharedUserClientOutputSizing");
}

void Patches::validateAMDDetailedTiming(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (!NVRAMArgs::shouldEnableAMDLinkValidationPatch()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping validateAMDDetailedTiming.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping validateAMDDetailedTiming.");
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN16AtiDeviceControl16notifyLinkChangeE31kAGDCRegisterLinkControlEvent_tmj",
        FunctionHooks::atiDeviceControlNotifyLinkChange,
        FunctionHooks::atiDeviceControlNotifyLinkChangeOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "validateAMDDetailedTiming");
}

void Patches::relaxAMDFramebufferTimingValidation(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (!NVRAMArgs::shouldEnableAMDFramebufferValidationPatch()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping relaxAMDFramebufferTimingValidation.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping relaxAMDFramebufferTimingValidation.");
        return;
    }

    KernelPatcher::RouteRequest request(
        "__ZN14AMDFramebuffer22validateDetailedTimingEPvy",
        FunctionHooks::amdFramebufferValidateDetailedTiming,
        FunctionHooks::amdFramebufferValidateDetailedTimingOriginal()
    );

    patchApplicator.applyRoutingPatch(index, patcher, &request, address, size, "relaxAMDFramebufferTimingValidation");
}

void Patches::forceAMD24BitOutput(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size, KernelPatcher::KextInfo *kext) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (!NVRAMArgs::shouldEnableAMD24BitOutputClamp()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping forceAMD24BitOutput.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping forceAMD24BitOutput.");
        return;
    }

    auto bitsPerComponent = patcher.solveSymbol<int *>(index, amdBitsPerComponentSymbol, address, size, false);
    if (bitsPerComponent != nullptr) {
        while (*bitsPerComponent != 0) {
            if (*bitsPerComponent == 10) {
                auto status = MachInfo::setKernelWriting(true, KernelPatcher::kernelWriteLock);
                if (status == KERN_SUCCESS) {
                    SYSLOG(moduleName, "Normalising AMD BITS_PER_COMPONENT from 10 to 8.");
                    *bitsPerComponent = 8;
                    MachInfo::setKernelWriting(false, KernelPatcher::kernelWriteLock);
                } else {
                    SYSLOG(moduleName, "Failed to disable write protection for AMD BITS_PER_COMPONENT.");
                    patcher.clearError();
                }
            }

            bitsPerComponent++;
        }
    } else {
        SYSLOG(moduleName, "Failed to resolve AMD BITS_PER_COMPONENT symbol.");
        patcher.clearError();
    }

    static const uint8_t find[] = "--RRRRRRRRRRGGGGGGGGGGBBBBBBBBBB";
    static const uint8_t repl[] = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
    KernelPatcher::LookupPatch patch = {kext, find, repl, sizeof(find) - 1, 2};
    patchApplicator.applyLookupPatch(patcher, &patch, "forceAMD24BitOutput");

    static const uint8_t bitsFind[] = {
        0x05, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x0A, 0x00, 0x00, 0x00,
        0x10, 0x00, 0x00, 0x00,
        0x10, 0x00, 0x00, 0x00
    };
    static const uint8_t bitsRepl[] = {
        0x05, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x08, 0x00, 0x00, 0x00,
        0x10, 0x00, 0x00, 0x00,
        0x10, 0x00, 0x00, 0x00
    };
    KernelPatcher::LookupPatch bitsPatch = {kext, bitsFind, bitsRepl, sizeof(bitsFind), 2};
    patchApplicator.applyLookupPatch(patcher, &bitsPatch, "forceAMD24BitOutput-bits");
}

void Patches::guardAMDIOSurfacePlaneInfo(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (!NVRAMArgs::isAMD()) {
        return;
    }

    if (!NVRAMArgs::shouldEnableAMDIOSurfaceGuard()) {
        return;
    }

    if (NVRAMArgs::isProbeMode()) {
        SYSLOG(moduleName, "Probe mode enabled, skipping guardAMDIOSurfacePlaneInfo.");
        return;
    }

    if (NVRAMArgs::shouldSkipAllPatches()) {
        SYSLOG(moduleName, "Global skip enabled, skipping guardAMDIOSurfacePlaneInfo.");
        return;
    }

    const uint8_t find[] = {0x41, 0x83, 0xbd, 0xb0, 0x00, 0x00, 0x00, 0x00, 0x74, 0x5c};
    const uint8_t repl[] = {0x45, 0x85, 0xe4, 0x74, 0x61, 0x85, 0xc9, 0x74, 0x5d, 0x90};
    KernelPatcher::LookupPatch patch = {kext, find, repl, sizeof(find), 1};
    patchApplicator.applyLookupPatch(patcher, &patch, "guardAMDIOSurfacePlaneInfo");
}

void Patches::bypassPCITunnelled(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (!NVRAMArgs::isNVDA() && !NVRAMArgs::isAMD()) {
        return;
    }

    if (shouldSkipPatch("bypassPCITunnelled", NVRAMArgs::shouldSkipIOGFXPatch())) {
        return;
    }
    
    const uint8_t find[] = {0x49, 0x4f, 0x50, 0x43, 0x49, 0x54, 0x75, 0x6e, 0x6e, 0x65, 0x6c, 0x6c, 0x65, 0x64};
    const uint8_t repl[] = {0x49, 0x4f, 0x50, 0x43, 0x49, 0x54, 0x75, 0x6e, 0x6e, 0x65, 0x6c, 0x6c, 0x65, 0x71};
    KernelPatcher::LookupPatch patch = {kext, find, repl, sizeof(find), 1};
    patchApplicator.applyLookupPatch(patcher, &patch, "bypassPCITunnelled");
}

void Patches::relaxGraphicsDevicePolicy(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (!NVRAMArgs::isNVDA() && !NVRAMArgs::isAMD()) {
        return;
    }

    if (shouldSkipPatch("relaxGraphicsDevicePolicy", NVRAMArgs::shouldSkipAGDPPatch())) {
        return;
    }

    // Mirror WhateverGreen's default external GPU AGDP relaxers:
    // 1. vit9696: disable board-id compare mode.
    const uint8_t vitFind[] = {0xBA, 0x05, 0x00, 0x00, 0x00};
    const uint8_t vitRepl[] = {0xBA, 0x00, 0x00, 0x00, 0x00};
    KernelPatcher::LookupPatch vitPatch = {kext, vitFind, vitRepl, sizeof(vitFind), 1};
    patchApplicator.applyLookupPatch(patcher, &vitPatch, "relaxGraphicsDevicePolicy-vit9696");

    // 2. pikera: force AGDP board-id lookup miss to fall back to permissive policy.
    const uint8_t pikFind[] = {0x62, 0x6f, 0x61, 0x72, 0x64, 0x2d, 0x69, 0x64}; // "board-id"
    const uint8_t pikRepl[] = {0x62, 0x6f, 0x61, 0x72, 0x64, 0x2d, 0x69, 0x78}; // "board-ix"
    KernelPatcher::LookupPatch pikPatch = {kext, pikFind, pikRepl, sizeof(pikFind), 1};
    patchApplicator.applyLookupPatch(patcher, &pikPatch, "relaxGraphicsDevicePolicy-pikera");
}

void Patches::bypassIOPCITunnelCompatible(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (shouldSkipPatch("bypassIOPCITunnelCompatible", NVRAMArgs::shouldSkipIOPCIPatch())) {
        return;
    }

    KernelPatcher::LookupPatch patch;
    switch (getKernelVersion()) {
        case KernelVersion::HighSierra:
        case KernelVersion::Mojave: {
            const uint8_t find[] = {0xff, 0x90, 0xa8, 0x02, 0x00, 0x00, 0x48, 0x85, 0xc0, 0x0f, 0x84, 0xbc, 0x00, 0x00, 0x00};
            const uint8_t repl[] = {0xff, 0x90, 0xa8, 0x02, 0x00, 0x00, 0x48, 0x85, 0xc0, 0x48, 0xe9, 0xbc, 0x00, 0x00, 0x00};
            patch = {kext, find, repl, sizeof(find), 1};
            break;
        }
        case KernelVersion::Sequoia: {
            const uint8_t find[] = {0xff, 0x90, 0xa8, 0x02, 0x00, 0x00, 0x48, 0x85, 0xc0, 0x0f, 0x84, 0xd1, 0x00, 0x00, 0x00};
            const uint8_t repl[] = {0xff, 0x90, 0xa8, 0x02, 0x00, 0x00, 0x48, 0x85, 0xc0, 0x48, 0xe9, 0xd1, 0x00, 0x00, 0x00};
            patch = {kext, find, repl, sizeof(find), 1};
            break;
        }
        default: {
            const uint8_t find[] = {0xff, 0x90, 0xa8, 0x02, 0x00, 0x00, 0x48, 0x85, 0xc0, 0x0f, 0x84, 0xb9, 0x00, 0x00, 0x00};
            const uint8_t repl[] = {0xff, 0x90, 0xa8, 0x02, 0x00, 0x00, 0x48, 0x85, 0xc0, 0x48, 0xe9, 0xb9, 0x00, 0x00, 0x00};
            patch = {kext, find, repl, sizeof(find), 1};
            break;
        }
    }
    patchApplicator.applyLookupPatch(patcher, &patch, "bypassIOPCITunnelCompatible");
}

void Patches::updateMuxControlNVRAMVar(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (shouldSkipPatch("updateMuxControlNVRAMVar", NVRAMArgs::shouldSkipMuxPatch())) {
        return;
    }

    const uint8_t find[] = {0x46, 0x41, 0x34, 0x43, 0x45, 0x32, 0x38, 0x44, 0x2d, 0x42, 0x36, 0x32, 0x46, 0x2d,
        0x34, 0x43, 0x39, 0x39, 0x2d, 0x39, 0x43, 0x43, 0x33, 0x2d, 0x36, 0x38, 0x31,
        0x35, 0x36, 0x38, 0x36, 0x45, 0x33, 0x30, 0x46, 0x39, 0x3a, 0x67, 0x70, 0x75,
        0x2d, 0x70, 0x6f, 0x77, 0x65, 0x72, 0x2d, 0x70, 0x72, 0x65, 0x66, 0x73};
    const uint8_t repl[] = {0x46, 0x41, 0x34, 0x43, 0x45, 0x32, 0x38, 0x44, 0x2d, 0x42, 0x36, 0x32, 0x46, 0x2d,
        0x34, 0x43, 0x39, 0x39, 0x2d, 0x39, 0x43, 0x43, 0x33, 0x2d, 0x36, 0x38, 0x31,
        0x35, 0x36, 0x38, 0x36, 0x45, 0x33, 0x30, 0x46, 0x39, 0x3a, 0x67, 0x70, 0x75,
        0x2d, 0x70, 0x6f, 0x77, 0x65, 0x72, 0x2d, 0x70, 0x72, 0x65, 0x66, 0x71};
    KernelPatcher::LookupPatch patch = {kext, find, repl, sizeof(find), 1};
    patchApplicator.applyLookupPatch(patcher, &patch, "updateMuxControlNVRAMVar");
}

void Patches::routeThunderboltEnumeration(KernelPatcher &patcher, size_t *index, mach_vm_address_t *address, size_t *size) {
    if (shouldSkipPatch("routeThunderboltEnumeration", NVRAMArgs::shouldSkipTBRoutePatch())) {
        return;
    }

    if (!NVRAMArgs::skipThunderboltEnum()) {
        SYSLOG("Kryptonite", "Skipping Thunderbolt enumeration patch because skipthunderboltenum is not set.");
        return;
    }

    mach_vm_address_t orgSkipEnumerationCallback {0};
    KernelPatcher::RouteRequest request("__ZN24IOThunderboltSwitchType321shouldSkipEnumerationEv", FunctionHooks::thunderboltShouldSkipEnumeration, {orgSkipEnumerationCallback});
    patchApplicator.applyRoutingPatch(*index, patcher, &request, *address, *size, "routeThunderboltEnumeration");
}

void Patches::applySequoiaPatch(KernelPatcher &patcher, KernelPatcher::KextInfo *kext) {
    if (shouldSkipPatch("applySequoiaPatch", NVRAMArgs::shouldSkipSequoiaPatch())) {
        return;
    }

    if (!Compatibility::isSequoiaForced()) {
        SYSLOG("Kryptonite", "Skipping Sequoia patch because kryfsequoia is not set.");
        return;
    }

    // Example patch for Sequoia. Replace this with actual bytes to patch if needed.
    const uint8_t find[] = {0x08, 0x00, 0x00, 0x00, 0x48, 0x04, 0x00, 0x00};
    const uint8_t repl[] = {0x09, 0x00, 0x00, 0x00, 0x30, 0x05, 0x00, 0x00};

    KernelPatcher::LookupPatch patch = {kext, find, repl, sizeof(find), 1};
    SYSLOG("Kryptonite", "Applying Sequoia-specific patch...");
    patchApplicator.applyLookupPatch(patcher, &patch, "applySequoiaPatch");
}
