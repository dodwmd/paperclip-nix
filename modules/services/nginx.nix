{ ... }:

let
  serverName = "zoe.home.dodwell.us";
  upstreamUrl = "http://127.0.0.1:3100";
in
{
  services.nginx = {
    enable = true;

    # Recommended defaults
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Write logs to files so fail2ban can parse them
    # (NixOS defaults to journald-only which fail2ban nginx filters can't read)
    commonHttpConfig = ''
      access_log /var/log/nginx/access.log;
      error_log /var/log/nginx/error.log;
    '';

    # Define the rate-limiting zone referenced by locations."/api/".extraConfig below.
    # (recommendedOptimisation covers server_tokens/client_max_body_size; nothing else needed here.)
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    '';

    virtualHosts.${serverName} = {
      default = true;

      # Security headers
      extraConfig = ''
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header X-XSS-Protection "0" always;
        add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self'; object-src 'none'; frame-ancestors 'self';" always;
      '';

      locations."/" = {
        proxyPass = upstreamUrl;
        proxyWebsockets = true;
      };

      # Rate-limit API endpoints more aggressively
      locations."/api/" = {
        proxyPass = upstreamUrl;
        proxyWebsockets = true;
        extraConfig = ''
          limit_req zone=api burst=20 nodelay;
          limit_req_status 429;
        '';
      };
    };
  };

  # Open port 80 for HTTP
  networking.firewall.allowedTCPPorts = [ 80 ];

  # Ensure nginx log directory and files exist with correct ownership.
  # fail2ban nginx-limit-req jail requires the log files to exist at startup.
  systemd.tmpfiles.rules = [
    "d /var/log/nginx 0750 nginx nginx -"
    "f /var/log/nginx/access.log 0640 nginx nginx -"
    "f /var/log/nginx/error.log 0640 nginx nginx -"
  ];

  # Override the built-in nginx logrotate entry to keep 14 days instead of 26
  services.logrotate.settings.nginx.rotate = 14;
}
