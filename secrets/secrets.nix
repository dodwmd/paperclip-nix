# Agenix encryption keys
# All secrets are encrypted with both user + host keys.
#
# The host key is PRE-GENERATED. The private key is stored age-encrypted
# (ssh_host_ed25519_key.age) and decrypted locally at install time to inject
# into the NUC via nixos-anywhere --extra-files.
#
# To regenerate: make generate-host-keys
# Then: make rekey  (re-encrypt all secrets with the new host key)
let
  # User key (dodwmd@exodus — your workstation)
  user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII1Vk18qExSQM6rksG500xD/mgACFpNyh7mRnrhVVUQx dodwmd@exodus";

  # Host key (root@paperclip — pre-generated, public key committed as plaintext)
  host = builtins.readFile ./host-keys/ssh_host_ed25519_key.pub;

  allKeys = [ user host ];
in
{
  # Host private key — encrypted with user key only (bootstrap secret)
  "ssh_host_ed25519_key.age".publicKeys = [ user ];

  # App secrets — encrypted with both user + host keys
  "db-password.age".publicKeys = allKeys;
  "paperclip-env.age".publicKeys = allKeys;
  "github-pat.age".publicKeys = allKeys;

  # Paperclip master key for secrets encryption (deployed to ~/.paperclip/instances/default/secrets/master.key)
  "paperclip-master-key.age".publicKeys = allKeys;

  # Cloudflare API token for ACME DNS challenge
  "cloudflare-credentials.age".publicKeys = allKeys;
}
