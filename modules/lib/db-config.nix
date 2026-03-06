# Shared database configuration constants.
# Import and reference to avoid duplication across modules.
# Example: let dbCfg = import ../lib/db-config.nix; in dbCfg.name
{
  name = "paperclip";
  user = "paperclip";
  host = "127.0.0.1";
  port = "5432";
}
