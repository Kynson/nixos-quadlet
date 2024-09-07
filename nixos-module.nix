{ libUtils }:
{ config, lib, pkgs, ... }@attrs:

with lib;

let
  cfg = config.virtualisation.quadlet;
  quadletUtils = import ./utils.nix {
    inherit lib;
    systemdLib = (libUtils {
      inherit lib config pkgs;
    }).systemdUtils.lib;
  };
  # TODO: replace with lib.mergeAttrsList once stable.
  mergeAttrsList = foldl mergeAttrs {};

  containerOpts = types.submodule (import ./container.nix { inherit quadletUtils; } );
  networkOpts = types.submodule (import ./network.nix { inherit quadletUtils pkgs; } );
in {
  imports = [
    ./network-online-service.nix
  ];

  options = {
    virtualisation.quadlet = {
      containers = mkOption {
        type = types.attrsOf containerOpts;
        default = { };
      };

      networks = mkOption {
        type = types.attrsOf networkOpts;
        default = { };
      };

      containersOwnerUID = mkOption {
        type = types.int;
        default = 0;
      };
    };
  };

  config = let
    allObjects = (attrValues cfg.containers) ++ (attrValues cfg.networks);
    containersOwnerUID = cfg.containersOwnerUID;
    containersOwnerUIDString = builtins.toString cfg.containersOwnerUID;
  in {
    virtualisation.podman.enable = true;
    environment.etc = mergeAttrsList (
      map (p: {
        "containers/systemd/users/${containersOwnerUIDString}/${p._configName}" = {
          text = p._configText;
          mode = "0600";
          uid = containersOwnerUID;
        };
      }) allObjects);
    # The symlinks are not necessary for the services to be honored by systemd,
    # but necessary for NixOS activation process to pick them up for updates.
    systemd.packages = [
      (pkgs.linkFarm "quadlet-service-symlinks" (
        map (p: {
          name = "etc/systemd/user/${containersOwnerUIDString}/${p._unitName}";
          path = "/run/user/${containersOwnerUIDString}/systemd/generator/${p._unitName}";
        }) allObjects))
    ];
    # Inject X-Restart-Triggers=${hash} for NixOS to detect changes.
    # Note that currently NixOS does not compare user unit for restart. See https://github.com/NixOS/nixpkgs/issues/246611
    systemd.user.units = mergeAttrsList (
      map (p: {
        ${p._unitName} = {
          overrideStrategy = "asDropin";
          text = ''
            [Unit]
            X-Restart-Triggers=${builtins.hashString "sha256" p._configText}
          '';
        };
      }) allObjects);
  };
}
