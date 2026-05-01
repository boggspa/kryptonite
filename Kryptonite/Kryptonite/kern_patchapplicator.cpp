//
//  kern_patchapplicator.cpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#include "kern_patchapplicator.hpp"

void PatchApplicator::applyLookupPatch(KernelPatcher& patcher, KernelPatcher::LookupPatch* patch, const char *patchName) {
    const char *target = patch && patch->kext ? patch->kext->id : "kernel";
    SYSLOG(moduleName, "Applying %s on %s...", patchName, target);

    patcher.applyLookupPatch(patch);
    auto error = patcher.getError();
    if (error != KernelPatcher::Error::NoError) {
        SYSLOG(moduleName, "Skipping failed %s on %s (error %d).", patchName, target, static_cast<int>(error));
        patcher.clearError();
        return;
    }

    SYSLOG(moduleName, "Applied %s on %s.", patchName, target);
}

void PatchApplicator::applyRoutingPatch(size_t index, KernelPatcher &patcher, KernelPatcher::RouteRequest *patch, mach_vm_address_t address, size_t size, const char *patchName) {
    SYSLOG(moduleName, "Applying route %s...", patchName);

    bool routed = patcher.routeMultiple(index, patch, 1, address, size);
    auto error = patcher.getError();
    if (!routed || error != KernelPatcher::Error::NoError) {
        SYSLOG(moduleName, "Skipping failed route %s (routed %d, error %d).", patchName, routed, static_cast<int>(error));
        patcher.clearError();
        return;
    }

    SYSLOG(moduleName, "Applied route %s from %llu to %llu.",
           patchName,
           static_cast<unsigned long long>(patch->from),
           static_cast<unsigned long long>(patch->to));
}
