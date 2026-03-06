{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      # Limit authentication attempts per connection
      MaxAuthTries = 3;
      # Only allow known users (reject early for unknown usernames)
      AllowUsers = [ "root" "dodwmd" "agent" ];
      # Disconnect idle sessions after 15 minutes (3 x 300s intervals)
      ClientAliveInterval = 300;
      ClientAliveCountMax = 3;
    };
    # Only listen on ed25519 host key (strongest, smallest)
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
}
