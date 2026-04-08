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
    if (!PE_parse_boot_argn(sequoiaForceArg, &sequoiaForce, sizeof(sequoiaForce))) {
        SYSLOG(moduleName, "%s boot arg not found.", sequoiaForceArg);
        return;
    }

    if (sequoiaForce)
        SYSLOG(moduleName, "%s enabled: %d", sequoiaForceArg, sequoiaForce);
    else
        SYSLOG(moduleName, "%s explicitly disabled.", sequoiaForceArg);
}

void NVRAMArgs::init() {
    getGPU();
    getTBTVersion();
    getSequoiaForce();
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
    bool skip = false;
    PE_parse_boot_argn("skipthunderboltenum", &skip, sizeof(skip));
    return skip;
}

bool NVRAMArgs::isThunderbolt1() {
    return tbtVersion == 1;
}

bool NVRAMArgs::isThunderbolt2() {
    return tbtVersion == 2;
}
