# Ad blocking in every browser: uBlock Origin in Firefox and uBlock Origin Lite in
# Google Chrome, force-installed through browser policies (users can't remove them).
{
  programs.firefox.policies.ExtensionSettings."uBlock0@raymondhill.net" = {
    installation_mode = "force_installed";
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
    private_browsing = true;
  };

  # Only writes the policy files (also into /etc/opt/chrome, which Google Chrome reads);
  # it doesn't install Chromium. Chrome dropped Manifest V2 extensions, so the full
  # uBlock Origin no longer runs there; Lite is its Manifest V3 version.
  programs.chromium = {
    enable = true;
    extensions = [ "ddkjiahejlhfcafbddmgiahcphecmpfh" ]; # uBlock Origin Lite
  };
}
