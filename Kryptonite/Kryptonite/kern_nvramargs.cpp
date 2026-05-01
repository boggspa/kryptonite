//
//  kern_nvramargs.cpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#include "kern_nvramargs.hpp"
#include <Headers/kern_iokit.hpp>
#include <Headers/kern_api.hpp>

bool NVRAMArgs::sequoiaForce = false;
bool NVRAMArgs::probeMode = false;
bool NVRAMArgs::skipAllPatches = false;
bool NVRAMArgs::enableIntelAGDCDisabler = false;
bool NVRAMArgs::enableIntelForceOnline = false;
bool NVRAMArgs::enableAMDCompatibilityPatch = false;
bool NVRAMArgs::enableAMDSharedUserClientVariableOutput = false;
bool NVRAMArgs::enableAMDAccelPrime = false;
bool NVRAMArgs::enableAMDLinkValidationPatch = false;
bool NVRAMArgs::enableAMDFramebufferValidationPatch = false;
bool NVRAMArgs::enableAMD24BitOutputClamp = false;
bool NVRAMArgs::enableAMDIOSurfaceGuard = false;
bool NVRAMArgs::skipAGDCPatch = false;
bool NVRAMArgs::skipAGDPPatch = false;
bool NVRAMArgs::skipIOGFXPatch = false;
bool NVRAMArgs::skipIOPCIPatch = false;
bool NVRAMArgs::skipMuxPatch = false;
bool NVRAMArgs::skipTBRoutePatch = false;
bool NVRAMArgs::skipSequoiaPatch = false;

static bool parseBooleanBootArg(const char *name) {
    int intValue = 0;
    if (PE_parse_boot_argn(name, &intValue, sizeof(intValue))) {
        return intValue != 0;
    }

    return checkKernelArgument(name);
}

void NVRAMArgs::getGPU() {
    if (!PE_parse_boot_argn(gpuArg, &gpu, sizeof(gpu))) {
        SYSLOG(moduleName, "GPU vendor args not found.");
        return;
    }
    
    SYSLOG(moduleName, "GPU vendor: %s", gpu);
}

void NVRAMArgs::getTBTVersion() {
    if (!PE_parse_boot_argn(tbtVersionArg, &tbtVersion, sizeof(tbtVersion))) {
        SYSLOG(moduleName, "Thunderbolt version not provided.");
        return;
    }
    
    if (tbtVersion < 1 || tbtVersion > 5) {
        SYSLOG(moduleName, "Invalid or unsupported thunderbolt version provided.");
        return;
    }
    
    SYSLOG(moduleName, "Provided thunderbolt version: %d", tbtVersion);
}

void NVRAMArgs::getSequoiaForce() {
    int forceArgValue = 0;
    if (PE_parse_boot_argn(sequoiaForceArg, &forceArgValue, sizeof(forceArgValue))) {
        sequoiaForce = forceArgValue != 0;
        if (sequoiaForce) {
            SYSLOG(moduleName, "%s enabled: %d", sequoiaForceArg, sequoiaForce);
        } else {
            SYSLOG(moduleName, "%s explicitly disabled.", sequoiaForceArg);
        }
        return;
    }

    sequoiaForce = checkKernelArgument(sequoiaForceArg);
    if (sequoiaForce) {
        SYSLOG(moduleName, "%s enabled.", sequoiaForceArg);
    } else {
        SYSLOG(moduleName, "%s boot arg not found.", sequoiaForceArg);
    }
}

void NVRAMArgs::getPatchControls() {
    probeMode = parseBooleanBootArg(probeArg);
    skipAllPatches = parseBooleanBootArg(skipAllArg);
    enableIntelAGDCDisabler = parseBooleanBootArg(intelAGDCArg);
    enableIntelForceOnline = parseBooleanBootArg(intelForceOnlineArg);
    enableAMDCompatibilityPatch = parseBooleanBootArg(amdCompatibilityArg);
    enableAMDSharedUserClientVariableOutput = parseBooleanBootArg(amdSharedUserClientVariableOutputArg);
    enableAMDAccelPrime = parseBooleanBootArg(amdAccelPrimeArg);
    enableAMDLinkValidationPatch = parseBooleanBootArg(amdLinkArg);
    enableAMDFramebufferValidationPatch = parseBooleanBootArg(amdFramebufferValidationArg);
    enableAMD24BitOutputClamp = parseBooleanBootArg(amd24BitOutputArg);
    enableAMDIOSurfaceGuard = parseBooleanBootArg(amdIOSurfaceGuardArg);
    skipAGDCPatch = parseBooleanBootArg(skipAGDCArg);
    skipAGDPPatch = parseBooleanBootArg(skipAGDPArg);
    skipIOGFXPatch = parseBooleanBootArg(skipIOGFXArg);
    skipIOPCIPatch = parseBooleanBootArg(skipIOPCIArg);
    skipMuxPatch = parseBooleanBootArg(skipMuxArg);
    skipTBRoutePatch = parseBooleanBootArg(skipTBRouteArg);
    skipSequoiaPatch = parseBooleanBootArg(skipSequoiaArg);

    if (probeMode) {
        SYSLOG(moduleName, "%s enabled: patch writes/routing disabled.", probeArg);
    }

    if (skipAllPatches) {
        SYSLOG(moduleName, "%s enabled: all Kryptonite patches disabled.", skipAllArg);
    }

    if (enableIntelAGDCDisabler) {
        SYSLOG(moduleName, "%s enabled: routing Intel framebuffer AGDC callback disabler.", intelAGDCArg);
    }

    if (enableIntelForceOnline) {
        SYSLOG(moduleName, "%s enabled: forcing Intel framebuffer display status online.", intelForceOnlineArg);
    }

    if (enableAMDCompatibilityPatch) {
        SYSLOG(moduleName, "%s enabled: applying Polaris compatibility hardening patches.", amdCompatibilityArg);
    }

    if (enableAMDSharedUserClientVariableOutput) {
        SYSLOG(moduleName, "%s enabled: relaxing AMD shared user-client structure output sizing.", amdSharedUserClientVariableOutputArg);
    }

    if (enableAMDAccelPrime) {
        SYSLOG(moduleName, "%s enabled: forcing AMD accelerator/HWServices reprobe hooks.", amdAccelPrimeArg);
    }

    if (enableAMDLinkValidationPatch) {
        SYSLOG(moduleName, "%s enabled: normalising AMD AGDC detailed timing validation.", amdLinkArg);
    }

    if (enableAMDFramebufferValidationPatch) {
        SYSLOG(moduleName, "%s enabled: relaxing AMDFramebuffer timing validation.", amdFramebufferValidationArg);
    }

    if (enableAMD24BitOutputClamp) {
        SYSLOG(moduleName, "%s enabled: forcing Radeon 24-bit output masks.", amd24BitOutputArg);
    }

    if (enableAMDIOSurfaceGuard) {
        SYSLOG(moduleName, "%s enabled: guarding Radeon IOSurface plane metrics against zero divisors.", amdIOSurfaceGuardArg);
    }

    if (skipAGDCPatch) {
        SYSLOG(moduleName, "%s enabled: skipping AppleGPUWrangler patch.", skipAGDCArg);
    }

    if (skipAGDPPatch) {
        SYSLOG(moduleName, "%s enabled: skipping AppleGraphicsDevicePolicy patch.", skipAGDPArg);
    }

    if (skipIOGFXPatch) {
        SYSLOG(moduleName, "%s enabled: skipping IOGraphicsFamily patch.", skipIOGFXArg);
    }

    if (skipIOPCIPatch) {
        SYSLOG(moduleName, "%s enabled: skipping IOPCIFamily patch.", skipIOPCIArg);
    }

    if (skipMuxPatch) {
        SYSLOG(moduleName, "%s enabled: skipping AppleMuxControl patch.", skipMuxArg);
    }

    if (skipTBRoutePatch) {
        SYSLOG(moduleName, "%s enabled: skipping Thunderbolt route patch.", skipTBRouteArg);
    }

    if (skipSequoiaPatch) {
        SYSLOG(moduleName, "%s enabled: skipping Sequoia-specific patch.", skipSequoiaArg);
    }
}

void NVRAMArgs::init() {
    getGPU();
    getTBTVersion();
    getSequoiaForce();
    getPatchControls();
}

bool NVRAMArgs::isAMD() {
    return !strcmp(gpu, amd);
}

bool NVRAMArgs::isNVDA() {
    return !strcmp(gpu, nvda);
}

bool NVRAMArgs::shouldForceSequoia() {
    return sequoiaForce;
}

bool NVRAMArgs::skipThunderboltEnum() {
    return parseBooleanBootArg("skipthunderboltenum");
}

bool NVRAMArgs::isThunderbolt1() {
    return tbtVersion == 1;
}

bool NVRAMArgs::isThunderbolt2() {
    return tbtVersion == 2;
}

bool NVRAMArgs::isProbeMode() {
    return probeMode;
}

bool NVRAMArgs::shouldSkipAllPatches() {
    return skipAllPatches;
}

bool NVRAMArgs::shouldEnableIntelAGDCDisabler() {
    return enableIntelAGDCDisabler;
}

bool NVRAMArgs::shouldEnableIntelForceOnline() {
    return enableIntelForceOnline;
}

bool NVRAMArgs::shouldEnableAMDCompatibilityPatch() {
    return enableAMDCompatibilityPatch;
}

bool NVRAMArgs::shouldEnableAMDSharedUserClientVariableOutput() {
    return enableAMDSharedUserClientVariableOutput;
}

bool NVRAMArgs::shouldEnableAMDAccelPrime() {
    return enableAMDAccelPrime;
}

bool NVRAMArgs::shouldEnableAMDLinkValidationPatch() {
    return enableAMDLinkValidationPatch;
}

bool NVRAMArgs::shouldEnableAMDFramebufferValidationPatch() {
    return enableAMDFramebufferValidationPatch;
}

bool NVRAMArgs::shouldEnableAMD24BitOutputClamp() {
    return enableAMD24BitOutputClamp;
}

bool NVRAMArgs::shouldEnableAMDIOSurfaceGuard() {
    return enableAMDIOSurfaceGuard;
}

bool NVRAMArgs::shouldSkipAGDCPatch() {
    return skipAGDCPatch;
}

bool NVRAMArgs::shouldSkipAGDPPatch() {
    return skipAGDPPatch;
}

bool NVRAMArgs::shouldSkipIOGFXPatch() {
    return skipIOGFXPatch;
}

bool NVRAMArgs::shouldSkipIOPCIPatch() {
    return skipIOPCIPatch;
}

bool NVRAMArgs::shouldSkipMuxPatch() {
    return skipMuxPatch;
}

bool NVRAMArgs::shouldSkipTBRoutePatch() {
    return skipTBRoutePatch;
}

bool NVRAMArgs::shouldSkipSequoiaPatch() {
    return skipSequoiaPatch;
}
