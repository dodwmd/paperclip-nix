{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    google-cloud-sdk      # gcloud, gsutil, bq
    docker-compose
  ];
}
