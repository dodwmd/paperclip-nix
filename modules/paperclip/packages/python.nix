{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    python312
    python312Packages.pip
    python312Packages.virtualenv
    python312Packages.pyyaml
    python312Packages.requests
    python312Packages.boto3
    python312Packages.black
    python312Packages.ruff
    uv                    # fast Python package manager
  ];
}
