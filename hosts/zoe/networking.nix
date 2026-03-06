{ ... }:

{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      # Port 80 opened by nginx module
      # Port 3100 is localhost-only (behind nginx)
    ];
  };

  # Brute-force protection
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      # Multiply ban time on repeat offenders (1h, 2h, 4h, 8h, ...)
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # Cap at 1 week
    };
    jails = {
      # Ban IPs hitting nginx rate limits (429 responses)
      # nginx is configured to write error logs to /var/log/nginx/error.log (see nginx.nix)
      nginx-limit-req = {
        settings = {
          enabled = true;
          filter = "nginx-limit-req";
          logpath = "/var/log/nginx/error.log";
          maxretry = 10;
          findtime = "1m";
          bantime = "10m";
        };
      };
    };
  };
}
