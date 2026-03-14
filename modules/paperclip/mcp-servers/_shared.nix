# Shared constants for MCP server definitions.
# Import with: shared = import ./_shared.nix;
{
  serviceUser = "agent";
  serviceGroup = "users";
  agentHome = "/home/agent";
  mcpRestartDelay = "15s";
}
