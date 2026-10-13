# Third-party Plasma widgets the saved panel layouts (plasma-panels.nix) use. Installed
# system-wide so they're there on a fresh install; widgets from "Get New Widgets" live
# in ~/.local/share/plasma/plasmoids/, which deploy.sh doesn't save.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    plasma-panel-spacer-extended # luisbocanegra.panelspacer.extended
  ];
}
