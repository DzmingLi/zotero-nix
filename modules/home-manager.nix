{ config, lib, pkgs, ... }:

let
  cfg = config.programs.zotero;

  # Zotero (Firefox 140 ESR) extensions DB schema version.
  # Bump when zotero-standalone-build's bundled gecko version crosses an
  # XPIProvider DB_SCHEMA increment.
  schemaVersion = 37;

  extensionsJson = pkgs.runCommand "extensions.json"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      jq -s --argjson sv ${toString schemaVersion} \
        '{schemaVersion: $sv, addons: .}' \
        ${lib.concatMapStringsSep " " (p: "${p}/addon.json") cfg.plugins} \
        > $out
    '';

  userJs = pkgs.writeText "zotero-managed-user.js" ''
    user_pref("extensions.databaseSchema", ${toString schemaVersion});
    user_pref("extensions.autoDisableScopes", 0);
    user_pref("extensions.enabledScopes", 15);
    user_pref("xpinstall.signatures.required", false);
    user_pref("extensions.update.enabled", false);
    user_pref("extensions.update.autoUpdateDefault", false);
  '';

in
{
  options.programs.zotero = {
    enable = lib.mkEnableOption "Zotero with declarative plugin management";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zotero;
      defaultText = lib.literalExpression "pkgs.zotero";
      description = "The Zotero package to install.";
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "managed";
      description = ''
        Zotero profile name. The profile lives at
        <code>~/.zotero/zotero/&lt;profileName&gt;</code> and is registered in
        <code>profiles.ini</code> as default. Launch Zotero normally — it will
        pick this profile.
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        [ inputs.zotero-nix.packages.''${pkgs.system}.translate-for-zotero ]
      '';
      description = ''
        Zotero plugin derivations. Each must produce
        <code>$out/&lt;id&gt;.xpi</code> and <code>$out/addon.json</code>
        (use <code>mkZoteroPlugin</code> from this flake).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.activation.zotero-plugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _zdir="$HOME/.zotero/zotero"
      _profile="${cfg.profileName}"
      _pdir="$_zdir/$_profile"
      $DRY_RUN_CMD mkdir -p "$_pdir/extensions"

      # Sweep previously-managed XPI symlinks (anything pointing into the nix
      # store) so plugin removals from the flake propagate.
      for f in "$_pdir/extensions"/*.xpi; do
        [ -e "$f" ] || continue
        if [ -L "$f" ] && [[ "$(readlink "$f")" == /nix/store/* ]]; then
          $DRY_RUN_CMD rm -f "$f"
        fi
      done

      ${lib.concatMapStringsSep "\n" (p: ''
        for x in ${p}/*.xpi; do
          $DRY_RUN_CMD ln -sfn "$x" "$_pdir/extensions/$(basename "$x")"
        done
      '') cfg.plugins}

      $DRY_RUN_CMD install -m 644 ${extensionsJson} "$_pdir/extensions.json"
      $DRY_RUN_CMD install -m 644 ${userJs}        "$_pdir/user.js"

      # Register the profile in profiles.ini and make it default.
      _pini="$_zdir/profiles.ini"
      if [ ! -f "$_pini" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 /dev/stdin "$_pini" <<EOF
      [General]
      StartWithLastProfile=1

      EOF
      fi
      if ! grep -q "^Path=$_profile$" "$_pini"; then
        $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i 's/^Default=1$/Default=0/' "$_pini"
        cat >> "$_pini" <<EOF

      [Profile-${cfg.profileName}]
      Name=${cfg.profileName}
      IsRelative=1
      Path=${cfg.profileName}
      Default=1
      EOF
      fi
    '';
  };
}
