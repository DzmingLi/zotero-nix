{ lib, fetchurl, mkZoteroPlugin }:

{
  translate-for-zotero = mkZoteroPlugin {
    pname = "zotero-plugin-translate-for-zotero";
    version = "2.4.3";
    src = fetchurl {
      url = "https://github.com/windingwind/zotero-pdf-translate/releases/download/v2.4.3/translate-for-zotero.xpi";
      hash = "sha256-/EHaAKXQBg1F5l8URsiVg+GGxQBmpLLpCML+Y0wmM3I=";
    };
    meta = with lib; {
      description = "Translate PDFs, EPUBs, webpages, metadata, annotations, notes (Zotero plugin)";
      homepage = "https://github.com/windingwind/zotero-pdf-translate";
      license = licenses.agpl3Only;
      platforms = platforms.all;
    };
  };
}
