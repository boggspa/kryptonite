//
//  kern_hooks.cpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#include "kern_hooks.hpp"
#include "kern_nvramargs.hpp"
#include <Headers/kern_api.hpp>

int FunctionHooks::thunderboltShouldSkipEnumeration() {
    if (NVRAMArgs::skipThunderboltEnum()) {
        SYSLOG(moduleName, "Boot arg detected: skipping Thunderbolt enumeration.");
        return 1;
    }
    
    SYSLOG(moduleName, "Boot arg not present: proceeding with Thunderbolt enumeration.");
    return 0;
}
