# Claude Code CLI: a system-wide `claude` that installs the official native build into
# the running user's ~/.local on first use; that copy then keeps itself up to date.
{ pkgs, ... }:

let
  claude = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      curl
    ];
    text = ''
      real="$HOME/.local/bin/claude"
      if [ ! -x "$real" ]; then
        echo "Claude Code is not installed for $USER yet, installing it into ~/.local ..." >&2
        curl -fsSL https://claude.ai/install.sh | bash
      fi
      exec "$real" "$@"
    '';
  };
in
{
  environment.systemPackages = [ claude ];

  # The native build is a generic Linux binary that expects a normal dynamic loader.
  programs.nix-ld.enable = true;

  # Where the native build installs itself; once there, it shadows the wrapper above.
  environment.localBinInPath = true;
}
