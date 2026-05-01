//
//  kern_patches.hpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/4/21.
//

#ifndef kern_patches_hpp
#define kern_patches_hpp

#include <Headers/kern_api.hpp>

class Patches {
private:
    constexpr static const char* moduleName = "patches";
    
public:
    static void init();
    static void unblockLegacyThunderbolt(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
    static void disableIntelFramebufferAGDC(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void forceIntelFramebufferOnlineDisplays(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void bypassAMDProjectSelection(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void skipAMDVRAMTest(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void stabiliseAMDAccelConfig(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void relaxAMDSharedUserClientOutputSizing(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void relaxIOAccelSharedUserClientOutputSizing(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void validateAMDDetailedTiming(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void relaxAMDFramebufferTimingValidation(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size);
    static void forceAMD24BitOutput(KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size, KernelPatcher::KextInfo *kext);
    static void guardAMDIOSurfacePlaneInfo(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
    static void bypassPCITunnelled(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
    static void relaxGraphicsDevicePolicy(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
    static void bypassIOPCITunnelCompatible(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
    static void updateMuxControlNVRAMVar(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
    static void routeThunderboltEnumeration(KernelPatcher &patcher, size_t *index, mach_vm_address_t *address, size_t *size);
    static void applySequoiaPatch(KernelPatcher &patcher, KernelPatcher::KextInfo *kext);
};

#endif /* kern_patches_hpp */
