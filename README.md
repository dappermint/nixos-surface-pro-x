# nixos-surface-pro-x

NixOS image for the Surface Pro X (SQ2), built from [linux-surface](https://github.com/linux-surface/surface-pro-x)'s kernel and firmware.

## Flash

```sh
curl -L https://files.dappy.lgbt/nixos.img.zst | zstd -d | sudo dd of=/dev/sdX bs=4M
```

Checksums: [nixos.img.sha256](https://files.dappy.lgbt/nixos.img.sha256). Uncompressed: [nixos.img](https://files.dappy.lgbt/nixos.img).

Disable secure boot, then hold vol-down + power. You land in a shell as `nixos` with passwordless sudo; `nmtui` for wifi. A black screen of up to ~20 s while the GPU takes over is normal.

## Build

```sh
nix build .#image   # aarch64-linux
```

Optional, needs `--impure`: `SPX_SSH_KEYS=<authorized_keys>`, `SPX_WIFI=<file.nmconnection>`.

## Status

Untested on hardware so far. Works upstream: keyboard cover, single touch, USB, NVMe, wifi, bluetooth, GPU. Missing: audio, cameras, suspend, multitouch/pen (needs iptsd).
