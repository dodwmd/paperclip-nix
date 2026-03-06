# Shared systemd service hardening options.
# Import and merge with service-specific overrides via //.
# Example: (import ../lib/hardening.nix).base // { ReadWritePaths = [ ... ]; }
#
# Note: MemoryDenyWriteExecute is NOT included in base because Node.js V8 JIT
# requires W+X memory mappings. Add it explicitly for non-JIT services.
{
  base = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectClock = true;
    RestrictSUIDSGID = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    LockPersonality = true;
    PrivateTmp = true;
    PrivateDevices = true;
    SystemCallArchitectures = "native";
    # AF_NETLINK needed by some services for DNS resolution
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
    CapabilityBoundingSet = "";
    # Prevent SUID/SGID bits on created files
    UMask = "0077";
    # Remove all ambient capabilities
    AmbientCapabilities = "";
    # Filter system calls to a safe set
    SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
    SystemCallErrorNumber = "EPERM";
  };
}
