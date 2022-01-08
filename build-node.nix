{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, nodeDrvName
, nodeVersion
, nodeDownloadData
}:

stdenv.mkDerivation rec {
  pname = nodeDrvName;
  version = nodeVersion;

  src = fetchurl nodeDownloadData.${stdenv.hostPlatform.system};

  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
  ];

  nativeBuildInputs = lib.optionals stdenv.isLinux [
    autoPatchelfHook
  ];

  dontConfigure = true;
  dontBuild = true;
  doInstallCheck = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    cp -r bin $out/bin
    [ -d include ] && cp -r include $out/include
    cp -r lib $out/lib
    cp -r share $out/share

    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck

    export NPM_CONFIG_UPDATE_NOTIFIER=false
    $out/bin/node --version | grep -F "${version}"
    $out/bin/npm --version

    runHook postInstallCheck
  '';

  postFixup = ''
    grep -l -r '^#!/usr/bin/env node' $out/ | while read -r f; do
      echo "replacing $f shebang"
      substituteInPlace "$f" \
        --replace "#!/usr/bin/env node" "#!$out/bin/node"
    done
  '';

  meta = with lib; {
    supportedPlatforms = lib.attrNames nodeDownloadData;
    broken = nodeDownloadData.broken or false;
  };
}
