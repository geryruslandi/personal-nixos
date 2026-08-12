# Local Swagger UI reader — `swagger-read ./openapi.json`
{ pkgs, ... }:

let
  # Classic Swagger UI static files shipped by the swagger-ui-bundle pip package
  swaggerStatic = "${pkgs.python313Packages.swagger-ui-bundle}/lib/${pkgs.python313.libPrefix}/site-packages/swagger_ui_bundle/vendor/swagger-ui-4.15.5";

  swaggerRead = pkgs.writeShellScriptBin "swagger-read" ''
    set -euo pipefail

    SPEC="''${1:-}"
    PORT="''${PORT:-8080}"

    if [ -z "$SPEC" ] || [ ! -f "$SPEC" ]; then
      echo "Usage: swagger-read <openapi.json|openapi.yaml>" >&2
      echo "       PORT=9090 swagger-read ./openapi.json" >&2
      exit 1
    fi

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    cp -r "${swaggerStatic}"/. "$TMPDIR"/

    # Bundle external $refs (./other.yaml etc.) into a single spec file.
    # Falls back to copying the raw file if bundling fails.
    if ! ${pkgs.redocly}/bin/redocly bundle "$SPEC" -o "$TMPDIR/spec.json" --force >/dev/null 2>&1; then
      cp "$SPEC" "$TMPDIR/spec.json"
    fi

    rm -f "$TMPDIR/swagger-initializer.js"
    cat > "$TMPDIR/swagger-initializer.js" <<EOF
    window.onload = function() {
      window.ui = SwaggerUIBundle({
        url: "./spec.json",
        dom_id: '#swagger-ui',
        deepLinking: true,
        displayRequestDuration: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        plugins: [
          SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "StandaloneLayout"
      });
    };
    EOF

    # Serve the static bundle + spec on 127.0.0.1:$PORT
    python3 - "$PORT" "$TMPDIR" <<'PYEOF' &
    import http.server
    import mimetypes
    import os
    import sys

    port, serve_dir = int(sys.argv[1]), sys.argv[2]
    mimetypes.add_type("application/json", ".json")
    mimetypes.add_type("application/yaml", ".yaml")


    class Handler(http.server.SimpleHTTPRequestHandler):
        extensions_map = http.server.SimpleHTTPRequestHandler.extensions_map.copy()
        extensions_map.update({".yaml": "application/yaml", ".yml": "application/yaml"})

        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=serve_dir, **kwargs)

        def log_message(self, fmt, *args):
            pass


    os.chdir(serve_dir)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
    PYEOF

    SERVER_PID=$!
    trap 'kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$TMPDIR"' EXIT

    sleep 0.5
    echo "Serving $SPEC at http://127.0.0.1:$PORT/ (Ctrl+C to stop)"
    xdg-open "http://127.0.0.1:$PORT/" >/dev/null 2>&1 || true

    wait "$SERVER_PID"
  '';
in
{
  home.packages = [ swaggerRead ];
}
