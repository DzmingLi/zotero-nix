{ config, lib, pkgs, ... }:

let
  cfg = config.programs.zotero;

  # Zotero (Firefox 140 ESR) extensions DB schema version.
  # Bump when zotero-standalone-build's bundled gecko version crosses an
  # XPIProvider DB_SCHEMA increment.
  schemaVersion = 37;

  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # Mozilla profile layout differs by platform:
  #   Linux:  <dataDir>/<profileName>           with Path=<profileName>
  #   Darwin: <dataDir>/Profiles/<profileName>  with Path=Profiles/<profileName>
  profileSubdir =
    if isDarwin then "Profiles/${cfg.profileName}" else cfg.profileName;
  profileDir = "${cfg.dataDir}/${profileSubdir}";
  profilesIni = "${cfg.dataDir}/profiles.ini";

  # Mozilla XPIProvider only loads extensions whose `path` lies inside a
  # recognized scope dir (PROFILE/APP/SYSTEM). Rewrite each addon's path and
  # rootURI from the build-time nix-store path to the profile-scope symlink
  # the activation script drops into <profileDir>/extensions/. The symlink
  # still resolves to /nix/store, so loading happens directly from immutable
  # storage — only the path Mozilla sees is profile-scoped.
  extensionsJson = pkgs.runCommand "extensions.json"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      jq -s --argjson sv ${toString schemaVersion} \
            --arg extdir ${lib.escapeShellArg "${profileDir}/extensions"} \
        '{schemaVersion: $sv,
          addons: [ .[] | . + {
            path:    ($extdir + "/" + .id + ".xpi"),
            rootURI: ("jar:file://" + $extdir + "/" + .id + ".xpi!/")
          } ]}' \
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

    dataDir = lib.mkOption {
      type = lib.types.str;
      default =
        if isDarwin
        then "${config.home.homeDirectory}/Library/Application Support/Zotero"
        else "${config.home.homeDirectory}/.zotero/zotero";
      defaultText = lib.literalExpression ''
        if pkgs.stdenv.hostPlatform.isDarwin
        then "''${config.home.homeDirectory}/Library/Application Support/Zotero"
        else "''${config.home.homeDirectory}/.zotero/zotero"
      '';
      description = ''
        Directory containing Zotero's <code>profiles.ini</code> and the
        <code>Profiles/</code> subtree (macOS) or profile dirs directly (Linux).
      '';
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "managed";
      description = ''
        Zotero profile name. The profile lives at
        <code>&lt;dataDir&gt;/&lt;profileName&gt;</code> on Linux or
        <code>&lt;dataDir&gt;/Profiles/&lt;profileName&gt;</code> on macOS,
        and is registered in <code>profiles.ini</code> as default. Launch Zotero
        normally — it will pick this profile.
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
      _pdir=${lib.escapeShellArg profileDir}
      _pini=${lib.escapeShellArg profilesIni}
      _profile=${lib.escapeShellArg cfg.profileName}
      _path_field=${lib.escapeShellArg profileSubdir}

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
      if [ ! -f "$_pini" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 /dev/stdin "$_pini" <<EOF
      [General]
      StartWithLastProfile=1

      EOF
      fi
      if ! grep -q "^Path=$_path_field$" "$_pini"; then
        $DRY_RUN_CMD ${pkgs.gnused}/bin/sed -i 's/^Default=1$/Default=0/' "$_pini"
        cat >> "$_pini" <<EOF

      [Profile-$_profile]
      Name=$_profile
      IsRelative=1
      Path=$_path_field
      Default=1
      EOF
      fi
    '';
  };
}
