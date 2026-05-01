#!/bin/bash
sudo mkdir -p /Volumes/EFI-HYBRID
sudo mount -t msdos /dev/disk0s1 /Volumes/EFI-HYBRID 2>/dev/null || true
