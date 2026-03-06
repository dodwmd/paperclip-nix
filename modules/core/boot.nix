{ ... }:

{
  boot.loader.systemd-boot = {
    enable = true;
    # Disable boot menu editor — prevents gaining root shell via init=/bin/sh
    editor = false;
    # Limit stored generations to prevent /boot from filling up (512M ESP)
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel hardening — restrict unprivileged access to kernel features
  boot.kernel.sysctl = {
    # Restrict dmesg to root (prevents info leaks)
    "kernel.dmesg_restrict" = 1;
    # Restrict kernel pointer exposure
    "kernel.kptr_restrict" = 2;
    # Disable unprivileged BPF (common exploit vector)
    "kernel.unprivileged_bpf_disabled" = 1;
    # Restrict perf_event access
    "kernel.perf_event_paranoid" = 3;
    # Disable SysRq (not needed on a headless server)
    "kernel.sysrq" = 0;
    # Network hardening
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    # Reject source-routed packets (spoofing vector)
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    # Log martian packets (helps detect spoofing attempts)
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    # Protect against SYN flood attacks
    "net.ipv4.tcp_syncookies" = 1;
    # Ignore ICMP broadcast requests (Smurf attack mitigation)
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    # Ignore bogus ICMP error responses
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
  };

  # zram swap — 25% of RAM compressed with zstd
  zramSwap = {
    enable = true;
    memoryPercent = 25;
    algorithm = "zstd";
  };
}
