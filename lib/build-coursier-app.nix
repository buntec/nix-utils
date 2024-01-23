{ jdk, coursier, zip, unzip, coreutils, dos2unix, lib, stdenv, makeWrapper
, writeShellScript, ... }:

{ groupId, artifactId, version, pname ? artifactId, depsHash ? ""
, javaOpts ? [ ] }:

let
  coursier-cache = stdenv.mkDerivation {
    name = "${pname}-coursier-cache";

    dontUnpack = true;
    nativeBuildInputs = [ jdk coursier zip unzip coreutils dos2unix ];

    JAVA_HOME = "${jdk}";
    COURSIER_CACHE = "./coursier-cache/v1";
    COURSIER_ARCHIVE_CACHE = "./coursier-cache/arc";
    COURSIER_JVM_CACHE = "./coursier-cache/jvm";

    buildPhase = ''
      mkdir -p coursier-cache/v1
      cs fetch ${groupId}:${artifactId}:${version} \
        -r bintray:scalacenter/releases \
        -r sonatype:snapshots

      ${builtins.readFile ./canonicalize-jars.sh}
      canonicalizeJarsIn $COURSIER_CACHE
    '';

    installPhase = ''
      mkdir -p $out/coursier-cache
      cp -R ./coursier-cache $out
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "${depsHash}";
  };

in stdenv.mkDerivation rec {
  inherit pname version;

  dontUnpack = true;

  buildInputs = [ jdk ];
  nativeBuildInputs = [ makeWrapper coursier coursier-cache ];

  JAVA_HOME = "${jdk}";
  COURSIER_CACHE = "${coursier-cache}/coursier-cache/v1";
  COURSIER_ARCHIVE_CACHE = "${coursier-cache}/coursier-cache/arc";
  COURSIER_JVM_CACHE = "${coursier-cache}/coursier-cache/jvm";

  launcher = "${pname}-launcher";

  buildPhase = ''
    mkdir -p coursier-cache/v1
    cs bootstrap ${groupId}:${artifactId}:${version} --standalone -o ${launcher}
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp ${launcher} $out
    makeWrapper $out/${launcher} $out/bin/${pname} \
      --set JAVA_HOME ${jdk} \
      --add-flags "${
        lib.strings.concatStringsSep " " (builtins.map (s: "-J" + s) javaOpts)
      }"
  '';

}
