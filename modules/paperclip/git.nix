{ ... }:

{
  # System-level git config: credential helper reads GITHUB_TOKEN from env.
  # This applies to all users; individuals can override in their ~/.gitconfig.
  #
  # The empty `helper = ` line resets any previously configured helpers
  # (e.g. one written by `gh auth setup-git`) before our env-based helper
  # takes effect, so the static credentials file is never consulted.
  #
  # Per-company GitHub tokens are stored as Paperclip company secrets and
  # bound in each agent's adapterConfig.env as GITHUB_TOKEN. The heartbeat
  # resolves the secret at run-time and injects it into the subprocess env,
  # overriding the system-level GITHUB_TOKEN loaded from the age secret.
  environment.etc."gitconfig".text = ''
    [credential "https://github.com"]
        helper =
        helper = !f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f
  '';

  # Remove the static credentials file on each boot so it cannot shadow the
  # env-based helper above. Any github.com token already stored there would
  # be used for ALL companies; the env-based approach is per-invocation.
  systemd.tmpfiles.rules = [
    "r /home/agent/.config/git/credentials"
  ];
}
