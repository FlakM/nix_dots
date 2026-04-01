{ buildNpmPackage, fetchurl }:
buildNpmPackage {
  pname = "openclaw";
  version = "2026.3.13";

  src = fetchurl {
    url = "https://registry.npmjs.org/openclaw/-/openclaw-2026.3.13.tgz";
    hash = "sha256-ZxHZ+MTxK9vc1QkOaGXi7hQbjNo+qo8gJZMEQGog6Wo=";
  };

  postPatch = ''
    cp ${./openclaw-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-FFn7yzDkcjjm53m844a3GYiBZuD5jfM+JY1Gm5TklE4=";

  makeCacheWritable = true;
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  meta.mainProgram = "openclaw";
}
