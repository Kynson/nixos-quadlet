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

      containerOwnerUID = mkOption {
        type = types.int;
        default = 0;
      };
    };
  };

  config = let
    allObjects = (attrValues cfg.containers) ++ (attrValues cfg.networks);
    containerOwner = cfg.containerOwnerUID;
  in {
    virtualisation.podman.enable = true;
    environment.etc = mergeAttrsList (
      map (p: {
        "containers/systemd/users/${p._configName}" = {
          text = p._configText;
          mode = "0600";
          uid = containerOwnerUID;
        };
      }) allObjects);
    # The symlinks are not necessary for the services to be honored by systemd,
    # but necessary for NixOS activation process to pick them up for updates.
    systemd.packages = [
      (pkgs.linkFarm "quadlet-service-symlinks" (
        map (p: {
          name = "etc/systemd/user/${p._unitName}";
          path = "/run/systemd/generator/${p._unitName}";
        }) allObjects))
    ];
    # Inject X-RestartIfChanged=${hash} for NixOS to detect changes.
    systemd.units = mergeAttrsList (
      map (p: {
        ${p._unitName} = {
          overrideStrategy = "asDropin";
          text = "[Unit]\nX-RestartIfChanged=${builtins.hashString "sha256" p._configText}";
        };
      }) allObjects);
  };
}
