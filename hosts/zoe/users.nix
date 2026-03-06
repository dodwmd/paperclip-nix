{ ... }:

{
  # Primary admin user
  users.users.dodwmd = {
    isNormalUser = true;
    home = "/home/dodwmd";
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII1Vk18qExSQM6rksG500xD/mgACFpNyh7mRnrhVVUQx dodwmd@exodus"
    ];
  };

  # Agent user — runs paperclip service and agents
  # Dedicated SSH key for audit trail and blast-radius isolation from admin.
  # Private key: ~/.ssh/id_agent_paperclip (on admin workstation)
  # Connect: ssh -i ~/.ssh/id_agent_paperclip agent@zoe.home.dodwell.us
  # Uses rootless Docker instead of root daemon (see packages/default.nix)
  users.users.agent = {
    isNormalUser = true;
    home = "/home/agent";
    homeMode = "750"; # Restrict home directory — agent may store credentials
    extraGroups = []; # No docker group — uses rootless Docker
    # Subordinate UID/GID ranges for rootless Docker
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOf/0BFvHchyP/y5iPlgGjwjlZPsilOTuzc9SQHQfCRj agent@paperclip"
    ];
  };

  # Root access for nixos-anywhere remote provisioning only.
  # Admin key retained for emergency recovery and future re-provisioning.
  # SSH password auth is disabled — key-only access.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII1Vk18qExSQM6rksG500xD/mgACFpNyh7mRnrhVVUQx dodwmd@exodus"
  ];

  # Passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Allow agent to manage paperclip services without password
  security.sudo.extraRules = [
    {
      users = [ "agent" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart paperclip";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start paperclip-mcp-context7";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart paperclip-mcp-context7";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop paperclip-mcp-context7";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
