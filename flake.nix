{
  description = "A collection of nix utilities";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs, flake-utils }:
    let version = if (self ? rev) then self.rev else "dirty";
    in {

      lib = { makeBuildScalaApp = import ./build-scala-app.nix; };

    } // flake-utils.lib.eachDefaultSystem (system:

      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ];
        };
        buildScalaApp = pkgs.callPackage ./build-scala-app.nix { };
        test-app = buildScalaApp {
          inherit version;
          src = ./test/src;
          pname = "test-app";
          sha256 = "sha256-syetQWuxhKwpxFfjlTwFYnj359Ad0sXvVXaz7ty22ak=";
        };
      in { checks = test-app; }

    );
}
