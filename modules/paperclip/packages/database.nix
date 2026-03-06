{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    postgresql_17         # psql CLI
    sqlite
    pgcli                 # better psql
  ];
}
