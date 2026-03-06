{ config, ... }:

{
  # Tell agenix which host key to use for decryption.
  # This key is pre-generated and deployed via nixos-anywhere --extra-files
  # so secrets work from the very first boot.
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  age.secrets = {
    # PostgreSQL password for the paperclip DB user (single source of truth)
    db-password = {
      file = ../secrets/db-password.age;
      owner = "postgres";
      group = "postgres";
      mode = "0400";
    };

    # Paperclip environment file (API keys, etc. — DATABASE_URL built at runtime from db-password)
    paperclip-env = {
      file = ../secrets/paperclip-env.age;
      owner = "agent";
      group = "users";
      mode = "0400";
    };

    # GitHub PAT for private repo access
    github-pat = {
      file = ../secrets/github-pat.age;
      owner = "agent";
      group = "users";
      mode = "0400";
    };
  };
}
