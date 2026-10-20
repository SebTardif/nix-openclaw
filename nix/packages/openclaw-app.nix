{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.10.5";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.10.5/OpenClaw-2026.10.5.zip";
    hash = "sha256-17klCHGvg+e7LmWV+ze0zrbjvoUC6xVibE2bwqh9Mrk=";
    stripRoot = false;
  };

  dontUnpack = true;
  # Shebang fixups would invalidate the signed upstream app bundle.
  dontFixup = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
