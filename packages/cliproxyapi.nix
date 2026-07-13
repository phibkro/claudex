{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

buildGoModule rec {
  pname = "cliproxyapi";
  version = "7.2.72";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-mk2te2FypISUdzxroq7WpN5SeD3fdGoWQ+w0z6k6rw8=";
  };

  subPackages = [ "cmd/server" ];
  vendorHash = "sha256-vQU3hLDga5PMUwH4KSB3T5sZ1uPUgHQHeyQGJTKHIYs=";

  # Keep local-model mode quiet and prevent credential IDs (upstream derives
  # them from OAuth filenames) from entering the user journal. Provider names
  # remain visible so model-route audits retain an external referent.
  postPatch = ''
    substituteInPlace cmd/server/main.go \
      --replace-fail 'misc.StartAntigravityVersionUpdater(context.Background())' \
      'if !localModel { misc.StartAntigravityVersionUpdater(context.Background()) }'

    substituteInPlace sdk/cliproxy/auth/selector.go \
      --replace-fail 'truncateSessionID(primaryID), auth.ID, provider, model)' \
      'truncateSessionID(primaryID), auth.Provider, provider, model)' \
      --replace-fail 'truncateSessionID(primaryID), truncateSessionID(fallbackID), auth.ID, provider, model)' \
      'truncateSessionID(primaryID), truncateSessionID(fallbackID), auth.Provider, provider, model)'
    substituteInPlace sdk/cliproxy/service.go \
      --replace-fail 'op, auth.ID, err)' 'op, auth.Provider, err)'
    substituteInPlace internal/pluginhost/adapters.go \
      --replace-fail 'auth.ID, errModels)' 'auth.Provider, errModels)'
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X main.Commit=6279bb8a4c2835ff6ed99c6b85083b2afbefa681"
    "-X main.BuildDate=1970-01-01T00:00:00Z"
  ];

  postInstall = ''
    mv "$out/bin/server" "$out/bin/cliproxyapi"
  '';

  meta = {
    description = "Anthropic/OpenAI-compatible local proxy for coding-agent OAuth providers";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cliproxyapi";
    platforms = lib.platforms.linux;
  };
}
