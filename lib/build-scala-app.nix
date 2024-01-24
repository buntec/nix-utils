{ writeScript, strip-nondeterminism, runtimeShell, stdenv, jdk, graalvm-ce
, scala-cli, nodejs, clang, coreutils, llvmPackages, openssl, s2n-tls, which
, zlib, ... }:

{ src, pname, version, depsHash ? ""
, supported-platforms ? [ "jvm" "graal" "native" "node" ]
, scala-native-version ? null, js-module-kind ? "common", }:

let
  supports-jvm = builtins.elem "jvm" supported-platforms;
  supports-native = builtins.elem "native" supported-platforms;
  supports-graal = builtins.elem "graal" supported-platforms;
  supports-node = builtins.elem "node" supported-platforms;

  native-version-flag = if (scala-native-version != null) then
    "--native-version ${scala-native-version}"
  else
    "";

  js-module-flag = if (js-module-kind != null) then
    "--js-module-kind ${js-module-kind}"
  else
    "";

  make-buildinfo = ''
    cat << EOF > ./buildinfo.scala
    package gitsummary
    object BuildInfo {
      val name = "${pname}"
      val version = "${version}"
    }
    EOF
  '';

  graal-jdk = graalvm-ce;
  node = nodejs;

  native-packages =
    [ clang coreutils llvmPackages.libcxxabi openssl s2n-tls which zlib ];

  build-packages = [ jdk scala-cli ]
    ++ (if (supports-native || supports-graal) then native-packages else [ ]);

  # fixed-output derivation: we must hash the coursier caches created during the build
  coursier-cache = stdenv.mkDerivation {
    inherit src;
    name = "${pname}-coursier-cache";

    buildInputs = build-packages;
    nativeBuildInputs = [ coreutils strip-nondeterminism ];

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
      ${if supports-native then
        "scala-cli compile . --native ${native-version-flag} --java-home=${jdk} --server=false"
      else
        ""}
      ${if supports-node then
        "scala-cli compile . --js ${js-module-flag} --java-home=${jdk} --server=false"
      else
        ""}
      find $COURSIER_CACHE -name '*.jar' -type f -print0 | xargs -r0 strip-nondeterminism
    '';

    installPhase = ''
      mkdir -p $out/coursier-cache
      cp -R ./coursier-cache $out
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = depsHash;
  };

  scala-native-app = native-mode:
    stdenv.mkDerivation {
      inherit version src;
      pname = "${pname}-native";
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
          --native ${native-version-flag} \
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

  jvm-app = stdenv.mkDerivation {
    inherit version src;
    pname = "${pname}-jvm";
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
    stdenv.mkDerivation {
      inherit version src;
      pname = "${pname}-node";
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
          --js ${js-module-flag} \
          --js-mode ${js-mode} \
          --java-home=${jdk} \
          --server=false \
          -o main.js
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp main.js $out
        cat << EOF > ${pname}
        #!${runtimeShell}
        ${node}/bin/node $out/main.js
        EOF
        chmod +x ${pname}
        cp ${pname} $out/bin
      '';

    };

  node-app-dev = node-app "dev";
  node-app-release = node-app "release";

  graal-native-image-app = stdenv.mkDerivation {
    inherit version src;
    pname = "${pname}-graal";
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

in (if supports-native then {
  native-release-full = scala-native-app-release-full;
  native-release-fast = scala-native-app-release-fast;
  native-release-size = scala-native-app-release-size;
  native-debug = scala-native-app-debug;
} else
  { }) // (if supports-node then {
    node-release = node-app-release;
    node-dev = node-app-dev;
  } else
    { })
// (if supports-graal then { graal = graal-native-image-app; } else { })
// (if supports-jvm then { jvm = jvm-app; } else { })

