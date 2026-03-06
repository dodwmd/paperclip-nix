{ ... }:

{
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    historyLimit = 50000;
    extraConfig = ''
      set -g mouse on
      set -g status-interval 5
    '';
  };
}
