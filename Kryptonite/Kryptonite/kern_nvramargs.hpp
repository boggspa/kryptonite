//
//  kern_nvramargs.hpp
//  Kryptonite
//
//  Created by Mayank Kumar on 6/2/21.
//

#ifndef kern_nvramargs_hpp
#define kern_nvramargs_hpp

static char gpu[5];
static int tbtVersion;

class NVRAMArgs {
private:
    constexpr static const char* moduleName = "nvram";
    
    constexpr static const char* gpuArg = "krygpu";
    constexpr static const char* amd = "AMD";
    constexpr static const char* nvda = "NVDA";
    
    constexpr static const char* tbtVersionArg = "krytbtv";
    constexpr static const char* sequoiaForceArg = "kryfsequoia";
    constexpr static const char* probeArg = "kryprobe";
    constexpr static const char* skipAllArg = "kryskipall";
    constexpr static const char* intelAGDCArg = "kryigfxagdc";
    constexpr static const char* intelForceOnlineArg = "kryigfxonln";
    constexpr static const char* amdCompatibilityArg = "kryamdcompat";
    constexpr static const char* amdSharedUserClientVariableOutputArg = "kryamdshmvar";
    constexpr static const char* amdAccelPrimeArg = "kryamdaccelprime";
    constexpr static const char* amdLinkArg = "kryamdlink";
    constexpr static const char* amdFramebufferValidationArg = "kryamdfbval";
    constexpr static const char* amd24BitOutputArg = "kryrad24";
    constexpr static const char* amdIOSurfaceGuardArg = "kryamdsurfguard";
    constexpr static const char* skipAGDCArg = "kryskipagdc";
    constexpr static const char* skipAGDPArg = "kryskipagdp";
    constexpr static const char* skipIOGFXArg = "kryskipiogfx";
    constexpr static const char* skipIOPCIArg = "kryskipiopci";
    constexpr static const char* skipMuxArg = "kryskipmux";
    constexpr static const char* skipTBRouteArg = "kryskiptbroute";
    constexpr static const char* skipSequoiaArg = "kryskipseq";

    static bool sequoiaForce;
    static bool probeMode;
    static bool skipAllPatches;
    static bool enableIntelAGDCDisabler;
    static bool enableIntelForceOnline;
    static bool enableAMDCompatibilityPatch;
    static bool enableAMDSharedUserClientVariableOutput;
    static bool enableAMDAccelPrime;
    static bool enableAMDLinkValidationPatch;
    static bool enableAMDFramebufferValidationPatch;
    static bool enableAMD24BitOutputClamp;
    static bool enableAMDIOSurfaceGuard;
    static bool skipAGDCPatch;
    static bool skipAGDPPatch;
    static bool skipIOGFXPatch;
    static bool skipIOPCIPatch;
    static bool skipMuxPatch;
    static bool skipTBRoutePatch;
    static bool skipSequoiaPatch;

    static void getGPU();
    static void getTBTVersion();
    static void getSequoiaForce();
    static void getPatchControls();

public:
    static void init();
    static bool isAMD();
    static bool isNVDA();
    static bool shouldForceSequoia();
    static bool isThunderbolt1();
    static bool isThunderbolt2();
    static bool skipThunderboltEnum();
    static bool isProbeMode();
    static bool shouldSkipAllPatches();
    static bool shouldEnableIntelAGDCDisabler();
    static bool shouldEnableIntelForceOnline();
    static bool shouldEnableAMDCompatibilityPatch();
    static bool shouldEnableAMDSharedUserClientVariableOutput();
    static bool shouldEnableAMDAccelPrime();
    static bool shouldEnableAMDLinkValidationPatch();
    static bool shouldEnableAMDFramebufferValidationPatch();
    static bool shouldEnableAMD24BitOutputClamp();
    static bool shouldEnableAMDIOSurfaceGuard();
    static bool shouldSkipAGDCPatch();
    static bool shouldSkipAGDPPatch();
    static bool shouldSkipIOGFXPatch();
    static bool shouldSkipIOPCIPatch();
    static bool shouldSkipMuxPatch();
    static bool shouldSkipTBRoutePatch();
    static bool shouldSkipSequoiaPatch();
};

#endif /* kern_nvramargs_hpp */
