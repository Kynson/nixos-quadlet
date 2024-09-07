{
  systemd.user.services.network-online = {
    enable = true;
    description = "User level version of the system level target network-online.target";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/bash -c 'until systemctl is-active network-online.target; do sleep 1; done'";
      RemainAfterExit = "yes";
    };
    wantedBy = ["default.target"];
  };
}