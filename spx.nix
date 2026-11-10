{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}:
let
  kernel = pkgs.linuxManualConfig {
    version = "7.3.1";
    modDirVersion = "7.3.1";
    src = inputs.linux-surface;
    # the config linux-surface ships in its arch package for this branch
    configfile = "${inputs.kernel-configs}/dist/arch-v7.3.1.config";
    allowImportFromDerivation = true;
    features.efiBootStub = true;
  };
  # uncompressed and high priority so it shadows linux-firmware's generic WCN3990 board file
  firmware = lib.hiPrio (
    pkgs.runCommand "spx-firmware" { passthru.compressFirmware = false; } ''
      mkdir -p $out/lib
      cp -r ${inputs.spx-firmware}/firmware $out/lib/firmware
    ''
  );
  registration = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
in
{
  imports = [ "${modulesPath}/image/repart.nix" ];

  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "26.05";
  networking.hostName = "spx";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.kernelPackages = pkgs.linuxPackagesFor kernel;
  boot.kernelParams = [
    "efi=novamap"
    "clk_ignore_unused"
    "cfg80211.ieee80211_regdom=GE"
  ];
  # usb, nvme, ext4 and vfat are all built in; the default list names modules this config doesn't have
  boot.initrd.includeDefaultModules = false;
  # no TrEE/fTPM support on this device
  boot.initrd.systemd.tpm2.enable = false;
  boot.kernelModules = [ "qcom_pd_mapper" ];
  hardware.deviceTree = {
    enable = true;
    name = "qcom/sc8180x-surface-pro-x.dtb";
  };

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ firmware ];
  # the arch config only has FW_LOADER_COMPRESS_XZ
  hardware.firmwareCompression = "xz";
  hardware.graphics.enable = true;

  # no EFS partition reachable, so rmtfs serves zeroed files (linux-surface's rmtfs-dummy)
  systemd.packages = [
    pkgs.rmtfs
    pkgs.tqftpserv
  ];
  services.udev.packages = [ pkgs.rmtfs ];
  services.udev.extraRules = ''
    SUBSYSTEM=="uio", ATTR{name}=="rmtfs", SYMLINK+="qcom_rmtfs_uio1"
  '';
  systemd.services.rmtfs = {
    wantedBy = [ "multi-user.target" ];
    preStart = ''
      for f in modem_fs1 modem_fs2 modem_fsc modem_fsg modem_tuning; do
        [ -e /var/lib/rmtfs/$f ] || ${pkgs.coreutils}/bin/truncate -s 2M /var/lib/rmtfs/$f
      done
    '';
    serviceConfig = {
      StateDirectory = "rmtfs";
      ExecStart = [
        ""
        "${pkgs.rmtfs}/bin/rmtfs -r -s -o /var/lib/rmtfs"
      ];
    };
  };
  systemd.services.tqftpserv.wantedBy = [ "multi-user.target" ];

  boot.loader.systemd-boot = {
    enable = true;
    installDeviceTree = true;
  };
  boot.loader.efi.canTouchEfiVariables = false;

  image.repart = {
    enable = true;
    name = "spx-nixos";
    partitions = {
      "10-esp" = {
        contents = {
          "/EFI/BOOT/BOOTAA64.EFI".source =
            "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi";
          "/EFI/Linux/nixos-spx.efi".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          "/loader/loader.conf".source = pkgs.writeText "loader.conf" "timeout 5\n";
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "spx-esp";
          SizeMinBytes = "512M";
          SizeMaxBytes = "512M";
        };
      };
      "20-root" = {
        storePaths = [ config.system.build.toplevel ];
        contents."/nix-path-registration".source = "${registration}/registration";
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "spx-nixos";
          Minimize = "guess";
        };
      };
    };
  };

  boot.postBootCommands = ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      rm -f /nix-path-registration
    fi
  '';
  boot.growPartition = true;
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/spx-nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/spx-esp";
    fsType = "vfat";
    options = [ "nofail" ];
  };

  networking.networkmanager.enable = true;
  # optional wifi keyfile, SPX_WIFI=<nmconnection> --impure (the psk lands in the store and the image)
  environment.etc."NetworkManager/system-connections/home.nmconnection" =
    lib.mkIf (builtins.getEnv "SPX_WIFI" != "")
      {
        text = builtins.readFile (builtins.getEnv "SPX_WIFI");
        mode = "0600";
      };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # installer-style: console autologin, passwordless sudo, ssh only with keys baked in via SPX_SSH_KEYS=<file> --impure
  services.getty.autologinUser = "nixos";
  security.sudo.wheelNeedsPassword = false;
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    openssh.authorizedKeys.keys = lib.optionals (builtins.getEnv "SPX_SSH_KEYS" != "") (
      lib.filter (k: k != "") (lib.splitString "\n" (builtins.readFile (builtins.getEnv "SPX_SSH_KEYS")))
    );
  };
  environment.systemPackages = with pkgs; [
    git
    pciutils
    usbutils
  ];
}
