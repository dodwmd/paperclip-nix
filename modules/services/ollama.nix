{ lib, ... }:

{
  # Ollama — local LLM inference server (CPU-only on N5105)
  # API listens on 127.0.0.1:11434 by default.
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
  };

  # Allow agent to manage the ollama service without a password
  security.sudo.extraRules = lib.mkAfter [
    {
      users = [ "agent" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl start ollama";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart ollama";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop ollama";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
