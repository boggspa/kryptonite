![Header](./Resources/Header.png)

# Kryptonite Sequoia A1278 / Blackmagic eGPU Experimental Fork

This is an experimental fork of [mayankk2308/kryptonite](https://github.com/mayankk2308/kryptonite), published under the original GPL-3.0 license and with original project attribution preserved.

The upstream project enables external GPUs on Thunderbolt 1 and 2 Macs. This fork contains source-level experiments for a much narrower target: macOS Sequoia on a Mid-2012 MacBook Pro with a Blackmagic/Polaris eGPU. It is not a general-purpose replacement for upstream Kryptonite.

## Tested Matrix

- Host: MacBook Pro Mid-2012, model A1278
- macOS: 15.5 Sequoia
- eGPU: Blackmagic eGPU with AMD Radeon Pro RX50 / Polaris-class hardware
- Boot path: OpenCore/Kryptonite-based Thunderbolt eGPU handoff
- Driver payloads: user-supplied OCLP Universal Binaries and Apple system files

## What Is Included

- Kernel-side Kryptonite source changes for Sequoia-era AMD/Polaris compatibility experiments.
- Shell scripts used to prepare, validate, and recover the tested A1278 + Blackmagic eGPU setup.
- Source-only installer and patching workflow notes embedded in the scripts.

## What Is Not Included

This repository does not redistribute OCLP Universal Binaries, Apple GPU drivers, Apple system frameworks, patched system files, local probe bundles, compiled kexts, or release ZIPs.

OCLP Universal Binaries images may use the public password `password`; that is an OCLP distribution convention, not a project secret. Even so, those binaries remain external user-provided inputs and are not bundled here.

## Known Limitations

- Tested only on the hardware and OS matrix above.
- Many scripts are recovery/validation tools for one known working setup, not polished public installers.
- The experimental Swift GUI/helper app is not part of the supported public workflow for this branch.
- Incorrect use can make a macOS install unbootable. Keep a separate bootable recovery path and a known-good EFI backup.

## License

Kryptonite is GPL-3.0 licensed. See [LICENSE.md](./LICENSE.md).
