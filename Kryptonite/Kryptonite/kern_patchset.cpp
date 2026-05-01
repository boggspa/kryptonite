// Adapted from: https://github.com/coderobe/AzulPatcher4600

#include <Headers/kern_api.hpp>
#include <Headers/kern_iokit.hpp>

#include "kern_patchset.hpp"
#include "kern_targetkexts.hpp"
#include "kern_patches.hpp"

void PatchSet::init() {
    Patches::init();
    LiluAPI::Error error = lilu.onKextLoad(kextList, kextListSize,
                                           [](void* user, KernelPatcher& patcher, size_t index, mach_vm_address_t address, size_t size) {
        PatchSet* patchset = static_cast<PatchSet*>(user);
        patchset->processKext(patcher, index, address, size);
    }, this);
    
    if (error != LiluAPI::Error::NoError) {
        SYSLOG(moduleName, "Failed to register onKextLoad method: %d", error);
    }
}

void PatchSet::processKext(KernelPatcher& patcher, size_t index, mach_vm_address_t address, size_t size) {
    for (size_t i = 0; i < kextListSize; i++) {
        if (kextList[i].loadIndex != index) {
            continue;
        }
        
        SYSLOG(moduleName, "Found %s...", kextList[i].id);
        
        if (!strcmp(kextList[i].id, kextList[0].id)) {
            Patches::unblockLegacyThunderbolt(patcher, &kextList[i]);
            Patches::bypassPCITunnelled(patcher, &kextList[i]);
            Patches::applySequoiaPatch(patcher, &kextList[i]);
        }
        
        if (!strcmp(kextList[i].id, kextList[1].id)) {
            Patches::bypassPCITunnelled(patcher, &kextList[i]);
        }

        if (!strcmp(kextList[i].id, kextList[9].id)) {
            Patches::relaxGraphicsDevicePolicy(patcher, &kextList[i]);
        }

        if (!strcmp(kextList[i].id, kextList[10].id)) {
            Patches::disableIntelFramebufferAGDC(patcher, index, address, size);
            Patches::forceIntelFramebufferOnlineDisplays(patcher, index, address, size);
        }

        if (!strcmp(kextList[i].id, kextList[11].id)) {
            Patches::skipAMDVRAMTest(patcher, index, address, size);
            Patches::validateAMDDetailedTiming(patcher, index, address, size);
        }

        if (!strcmp(kextList[i].id, kextList[5].id)) {
            // AMD path: bypass IOPCITunnelled gate in AMDRadeonX4000 on newer systems.
            Patches::bypassPCITunnelled(patcher, &kextList[i]);
            Patches::stabiliseAMDAccelConfig(patcher, index, address, size);
            Patches::guardAMDIOSurfacePlaneInfo(patcher, &kextList[i]);
            // Patches::relaxAMDSharedUserClientOutputSizing(patcher, index, address, size);
        }

        if (!strcmp(kextList[i].id, kextList[7].id)) {
            Patches::bypassAMDProjectSelection(patcher, index, address, size);
        }

        if (!strcmp(kextList[i].id, kextList[8].id)) {
            Patches::relaxAMDFramebufferTimingValidation(patcher, index, address, size);
            Patches::forceAMD24BitOutput(patcher, index, address, size, &kextList[i]);
        }

        
        if (!strcmp(kextList[i].id, kextList[2].id)) {
            Patches::updateMuxControlNVRAMVar(patcher, &kextList[i]);
        }
        
        if (!strcmp(kextList[i].id, kextList[3].id)) {
            Patches::routeThunderboltEnumeration(patcher, &index, &address, &size);
        }
        
        if (!strcmp(kextList[i].id, kextList[4].id)) {
            Patches::bypassIOPCITunnelCompatible(patcher, &kextList[i]);
        }
    }
    
    patcher.clearError();
}
