# Syncthing Obsidian Vault Synchronization
#
# Architecture:
# =============
#
#                    ┌─────────────────────────────────────────────────────┐
#                    │                   SYNCTHING MESH                    │
#                    └─────────────────────────────────────────────────────┘
#
#     ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
#     │   amd-pc    │◄───────►│   odroid    │◄───────►│   pixel     │
#     │  (primary)  │         │  (24/7 hub) │         │  (mobile)   │
#     │ sendreceive │         │ encrypted   │         │ sendreceive │
#     └─────────────┘         └─────────────┘         └─────────────┘
#           ▲                       ▲                       ▲
#           │                       │                       │
#           ▼                       ▼                       ▼
#     ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
#     │    air      │◄───────►│    work     │         │             │
#     │   (macOS)   │         │   (macOS)   │         │             │
#     │ sendreceive │         │ sendreceive │         │             │
#     └─────────────┘         └─────────────┘         └─────────────┘
#
# Data Flow:
# ==========
#
#   amd-pc (~/obsidian/{work,family})
#      │
#      ├──► odroid: receives ENCRYPTED data at /var/lib/syncthing/encrypted/
#      │            (cannot decrypt - just stores encrypted blobs for relay)
#      │
#      ├──► pixel/air/work: receive full plaintext data
#      │
#      └──► All devices can sync through odroid when amd-pc is offline
#
# Vault Locations:
# ================
#
#   Device      │ work-vault            │ family-vault
#   ────────────┼───────────────────────┼─────────────────────────
#   amd-pc      │ ~/obsidian/work       │ ~/obsidian/family
#   pixel       │ ~/obsidian/work       │ ~/obsidian/family
#   air         │ ~/obsidian/work       │ ~/obsidian/family
#   work        │ ~/obsidian/work       │ ~/obsidian/family
#   odroid      │ (encrypted)           │ (encrypted)
#
# Encryption:
# ===========
#
#   - odroid uses "receiveencrypted" mode (cannot read vault contents)
#   - Encryption passwords stored in SOPS (syncthing_*_vault_password)
#   - Other devices use "sendreceive" with staggered versioning (1 year)
#
# Files:
# ======
#
#   shared/syncthing/
#   ├── default.nix   - Device registry and folder IDs (this file)
#   ├── amd-pc.nix    - Primary workstation config
#   └── odroid.nix    - Encrypted hub config
#
# Adding a New Device:
# ====================
#
#   1. Get device ID: syncthing -device-id
#   2. Add to devices below with placeholder ID
#   3. Add device name to allDevices in amd-pc.nix and odroid.nix
#   4. Rebuild NixOS on amd-pc and odroid
#   5. Accept folder shares on new device
#

{
  devices = {
    amd-pc = {
      id = "A7U2OJU-3CJI75V-266OPWB-KVUOLWG-PVQZQVO-OF5YOFF-AHON5ZC-MX573QI";
      name = "amd-pc";
    };
    odroid = {
      id = "YZG5N6S-5MGXTHA-HAOZUQ7-FMBC75O-VYZFST4-UYMTGL7-K72BUQX-MPXMQAM";
      name = "odroid";
    };
    pixel = {
      id = "CS543I2-6DUUOEB-EMPHN7L-KEMEWMD-CG5KS57-W24GPRA-JZA46Y6-UEPYXQ4";
      name = "pixel";
    };
    air = {
      id = "AIR-DEVICE-ID-PLACEHOLDER";
      name = "air";
    };
    work = {
      id = "WORK-DEVICE-ID-PLACEHOLDER";
      name = "work";
    };
  };

  folders = {
    family-vault = {
      id = "family-vault";
      label = "Obsidian Family Vault";
    };
    work-vault = {
      id = "work-vault";
      label = "Obsidian Work Vault";
    };
  };
}
