{ lib, stdenvNoCC, unzip, jq }:

{
  # Build a Zotero plugin derivation from an XPI source.
  # Output:
  #   $out/<id>.xpi   — the XPI, renamed to its addon id
  #   $out/addon.json — single addon entry for extensions.json
  #   $out/id         — the addon id, as plain text
  mkZoteroPlugin =
    { pname
    , version
    , src
    , meta ? { }
    }:
    stdenvNoCC.mkDerivation {
      inherit pname version src meta;
      dontUnpack = true;
      nativeBuildInputs = [ unzip jq ];

      buildPhase = ''
        runHook preBuild

        unzip -p $src manifest.json > manifest.json

        ID=$(jq -r '
          .applications.zotero.id //
          .applications.gecko.id //
          .browser_specific_settings.gecko.id //
          empty
        ' manifest.json)
        [ -n "$ID" ] || { echo "manifest has no addon id"; exit 1; }

        ADDON_VERSION=$(jq -r '.version' manifest.json)
        MIN=$(jq -r '
          .applications.zotero.strict_min_version //
          .applications.gecko.strict_min_version //
          "0"
        ' manifest.json)
        MAX=$(jq -r '
          .applications.zotero.strict_max_version //
          .applications.gecko.strict_max_version //
          "*"
        ' manifest.json)

        mkdir -p $out
        cp $src "$out/$ID.xpi"
        printf '%s' "$ID" > $out/id

        jq -n \
          --arg id        "$ID" \
          --arg version   "$ADDON_VERSION" \
          --arg min       "$MIN" \
          --arg max       "$MAX" \
          --arg path      "$out/$ID.xpi" \
          --arg rootURI   "jar:file://$out/$ID.xpi!/" \
          '{
            id: $id,
            syncGUID: ($id | @base64),
            version: $version,
            type: "extension",
            loader: null,
            optionsURL: null,
            optionsType: null,
            defaultLocale: { name: "", description: "" },
            visible: true,
            active: true,
            userDisabled: false,
            appDisabled: false,
            embedderDisabled: false,
            pendingUninstall: false,
            installDate: 1714000000000,
            updateDate: 1714000000000,
            applyBackgroundUpdates: 0,
            path: $path,
            skinnable: false,
            sourceURI: null,
            releaseNotesURI: null,
            softDisabled: false,
            foreignInstall: false,
            strictCompatibility: false,
            locales: [],
            targetApplications: [
              { id: "zotero@chnm.gmu.edu", minVersion: $min, maxVersion: $max }
            ],
            targetPlatforms: [],
            signedState: 0,
            seen: true,
            dependencies: [],
            userPermissions: null,
            optionalPermissions: null,
            icons: {},
            blocklistState: 0,
            blocklistURL: null,
            startupData: null,
            hidden: false,
            installTelemetryInfo: { source: "file-url" },
            recommendationState: null,
            rootURI: $rootURI
          }' > $out/addon.json

        runHook postBuild
      '';

      passthru.isZoteroPlugin = true;
    };
}
