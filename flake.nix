{
  description = "Node.js overlay";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      supportedSystems = [
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-linux"
        "x86_64-darwin"
      ];

      releases = builtins.fromJSON (builtins.readFile ./data/releases/_all.json);
    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        processVersion = nodeVersion:
          let
            release = builtins.fromJSON (builtins.readFile (./data/releases + "/${nodeVersion}.json"));
            releaseType = release.release_type;

            nodeDownloadData = builtins.removeAttrs release [ "release_type" ];
            nodeDrvName = "nodejs_${releaseType}";
            cleanVersion = builtins.replaceStrings [ "." ] [ "_" ] nodeVersion;
            nodeDrvName' = "${nodeDrvName}_${cleanVersion}";
          in
          if ((nodeDownloadData.${system} or null) != null) then
            {
              name = nodeDrvName';
              value = pkgs.callPackage ./build-node.nix {
                inherit nodeDrvName nodeDownloadData;
                nodeVersion = builtins.replaceStrings [ "v" ] [ "" ] nodeVersion;
              };
            }
          else null;
      in
      {
        packages = builtins.listToAttrs (builtins.filter (a: a != null) (map processVersion releases));
      });
}
