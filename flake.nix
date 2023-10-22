{
  description = "A collection of nix utilities";

  outputs = { self }: {

    lib = {

      buildScalaApp = { pkgs, src, pname, version, sha256
        , supported-platforms ? [ "jvm" "graal" "native" "node" ]
        , scala-native-version ? "0.4.15" }:

        let
          supports-jvm = builtins.elem "jvm" supported-platforms;
          supports-native = builtins.elem "native" supported-platforms;
          supports-graal = builtins.elem "graal" supported-platforms;
          supports-node = builtins.elem "node" supported-platforms;

          make-buildinfo = ''
            cat << EOF > ./buildinfo.scala
            package gitsummary
            object BuildInfo {
              val name = "${pname}"
              val version = "${version}"
            }
            EOF
          '';

          jdk = pkgs.jdk19_headless;
          graal-jdk = pkgs.graalvm-ce;
          scala-cli = pkgs.scala-cli.override { jre = jdk; };
          node = pkgs.nodejs;

          native-packages = [
            pkgs.clang
            pkgs.coreutils
            pkgs.llvmPackages.libcxxabi
            pkgs.openssl
            pkgs.s2n-tls
            pkgs.which
            pkgs.zlib
          ];

          build-packages = [ jdk scala-cli ]
            ++ (if (supports-native || supports-graal) then
              native-packages
            else
              [ ]);

          # fixed-output derivation: to nix'ify scala-cli,
          # we must hash the coursier caches created during the build
          coursier-cache = pkgs.stdenv.mkDerivation {
            inherit src;
            name = "${pname}-coursier-cache";

            buildInputs = build-packages;

            SCALA_CLI_HOME = "./scala-cli-home";
            COURSIER_CACHE = "./coursier-cache/v1";
            COURSIER_ARCHIVE_CACHE = "./coursier-cache/arc";
            COURSIER_JVM_CACHE = "./coursier-cache/jvm";

            # run the same build as our main derivation
            # to populate the cache with the correct set of dependencies
            buildPhase = ''
              mkdir scala-cli-home
              mkdir -p coursier-cache/v1
              mkdir -p coursier-cache/arc
              mkdir -p coursier-cache/jvm
              ${make-buildinfo}
              scala-cli compile . --java-home=${jdk} --server=false
              ${if (supports-native) then
                "scala-cli compile . --native --native-version ${scala-native-version} --java-home=${jdk} --server=false"
              else
                ""}
              ${if (supports-node) then
                "scala-cli compile . --js --js-module-kind common --java-home=${jdk} --server=false"
              else
                ""}
            '';

            installPhase = ''
              mkdir -p $out/coursier-cache
              cp -R ./coursier-cache $out
            '';

            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = sha256;
          };

          scala-native-app = native-mode:
            pkgs.stdenv.mkDerivation {
              inherit pname version src;
              buildInputs = build-packages ++ [ coursier-cache ];

              JAVA_HOME = "${jdk}";
              SCALA_CLI_HOME = "./scala-cli-home";
              COURSIER_CACHE = "${coursier-cache}/coursier-cache/v1";
              COURSIER_ARCHIVE_CACHE = "${coursier-cache}/coursier-cache/arc";
              COURSIER_JVM_CACHE = "${coursier-cache}/coursier-cache/jvm";

              buildPhase = ''
                mkdir scala-cli-home
                ${make-buildinfo}
                scala-cli --power \
                  package . \
                  --native \
                  --native-version ${scala-native-version} \
                  --native-mode ${native-mode} \
                  --java-home=${jdk} \
                  --server=false \
                  -o ${pname} 
              '';

              installPhase = ''
                mkdir -p $out/bin
                cp ${pname} $out/bin
              '';
            };

          scala-native-app-debug = scala-native-app "debug";
          scala-native-app-release-fast = scala-native-app "release-fast";
          scala-native-app-release-full = scala-native-app "release-full";
          scala-native-app-release-size = scala-native-app "release-size";

          jvm-app = pkgs.stdenv.mkDerivation {
            inherit pname version src;
            buildInputs = build-packages ++ [ coursier-cache ];

            JAVA_HOME = "${jdk}";
            SCALA_CLI_HOME = "./scala-cli-home";
            COURSIER_CACHE = "${coursier-cache}/coursier-cache/v1";
            COURSIER_ARCHIVE_CACHE = "${coursier-cache}/coursier-cache/arc";
            COURSIER_JVM_CACHE = "${coursier-cache}/coursier-cache/jvm";

            buildPhase = ''
              mkdir scala-cli-home
              ${make-buildinfo}
              scala-cli --power \
                package . \
                --standalone \
                --java-home=${jdk} \
                --server=false \
                -o ${pname} 
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp ${pname} $out/bin
            '';
          };

          node-app = js-mode:
            pkgs.stdenv.mkDerivation rec {
              inherit pname version src;
              buildInputs = build-packages ++ [ node coursier-cache ];

              JAVA_HOME = "${jdk}";
              SCALA_CLI_HOME = "./scala-cli-home";
              COURSIER_CACHE = "${coursier-cache}/coursier-cache/v1";
              COURSIER_ARCHIVE_CACHE = "${coursier-cache}/coursier-cache/arc";
              COURSIER_JVM_CACHE = "${coursier-cache}/coursier-cache/jvm";

              buildPhase = ''
                mkdir scala-cli-home
                ${make-buildinfo}
                scala-cli --power \
                  package . \
                  --js \
                  --js-module-kind common \
                  --js-mode ${js-mode} \
                  --java-home=${jdk} \
                  --server=false \
                  -o main.js
              '';

              wrapperScript = pkgs.writeScript "${pname}" ''
                #!${pkgs.runtimeShell}
                ${node}/bin/node $out/main.js
              '';

              installPhase = ''
                mkdir -p $out/bin
                cp main.js $out
                cp ${wrapperScript} $out/bin
              '';
            };

          node-app-dev = node-app "dev";
          node-app-release = node-app "release";

          graal-native-image-app = pkgs.stdenv.mkDerivation {
            inherit pname version src;
            buildInputs = build-packages ++ [ graal-jdk coursier-cache ];

            JAVA_HOME = "${graal-jdk}";
            SCALA_CLI_HOME = "./scala-cli-home";
            COURSIER_CACHE = "${coursier-cache}/coursier-cache/v1";
            COURSIER_ARCHIVE_CACHE = "${coursier-cache}/coursier-cache/arc";
            COURSIER_JVM_CACHE = "${coursier-cache}/coursier-cache/jvm";

            buildPhase = ''
              mkdir scala-cli-home
              ${make-buildinfo}
              scala-cli --power \
                package . \
                --native-image \
                --java-home ${graal-jdk} \
                --server=false \
                --graalvm-args --verbose \
                --graalvm-args --native-image-info \
                --graalvm-args --no-fallback \
                --graalvm-args --initialize-at-build-time=scala.runtime.Statics$$VM \
                --graalvm-args --initialize-at-build-time=scala.Symbol \
                --graalvm-args --initialize-at-build-time=scala.Symbol$$ \
                --graalvm-args -H:-CheckToolchain \
                --graalvm-args -H:+ReportExceptionStackTraces \
                --graalvm-args -H:-UseServiceLoaderFeature \
                -o ${pname}
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp ${pname} $out/bin
            '';
          };

        in (if (supports-native) then {
          native-release-full = scala-native-app-release-full;
          native-release-fast = scala-native-app-release-fast;
          native-release-size = scala-native-app-release-size;
          native-debug = scala-native-app-debug;
        } else
          { }) // (if (supports-node) then {
            node-release = node-app-release;
            node-dev = node-app-dev;
          } else
            { }) // (if (supports-graal) then {
              graal = graal-native-image-app;
            } else
              { }) // (if (supports-jvm) then { jvm = jvm-app; } else { });

    };

  };
}
