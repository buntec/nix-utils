{
  description = "A collection of nix utilities";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs.lib) genAttrs mapAttrs' nameValuePair;

      version = if (self ? rev) then self.rev else "dirty";

      eachSystem = genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

    in {

      lib = {
        mkBuildScalaApp = import ./lib/build-scala-app.nix;
        mkBuildCoursierApp = import ./lib/build-coursier-app.nix;
      };

      checks = eachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ ];
          };

          buildScalaApp = pkgs.callPackage self.lib.mkBuildScalaApp { };
          scala-test-app = buildScalaApp {
            inherit version;
            src = ./test/src;
            pname = "app";
            sha256 = "sha256-EQIgNMmrFQNHGsvbrAFmNFzpc50JMXddPdGDCg9C01o=";
          };

          buildCoursierApp = pkgs.callPackage self.lib.mkBuildCoursierApp { };
          coursier-test-app = buildCoursierApp {
            groupId = "org.scalameta";
            artifactId = "metals_2.13";
            version = "1.0.1";
            pname = "metals";
            depsHash = "sha256-WAQbkBcYxGjWKdC2NZHHYPha9i+b7f+xWO1LVsLkJeI=";
          };

        in (mapAttrs'
          (name: value: nameValuePair ("scala-test-app_" + name) (value))
          scala-test-app // {
            inherit coursier-test-app;
          }));

    };

}
