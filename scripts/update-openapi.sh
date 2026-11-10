#!/usr/bin/env bash
# Copies the backend's OpenAPI spec into the unit tests as JSON (TogetherTests/Resources/openapi.json), so
# APISpecTests check the client's wire models against the contract. Run after the spec changes:
#   scripts/update-openapi.sh            # from ../back, branch dev
#   scripts/update-openapi.sh main       # another branch or ref
set -euo pipefail
ref="${1:-dev}"
here="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$here/../back" show "$ref:api/openapi.yaml" \
  | ruby -rdate -ryaml -rjson -e '
      # macOS ships a YAML 1.1 parser: quote URLs inside flow mappings ({ example: https://… }) first.
      text = STDIN.read.force_encoding("UTF-8").gsub(/(:\s)(https?:\/\/[^,}\s]+)/) { "#{$1}\"#{$2}\"" }
      puts JSON.pretty_generate(YAML.safe_load(text, permitted_classes: [Date, Time]))' \
  > "$here/TogetherTests/Resources/openapi.json"
echo "TogetherTests/Resources/openapi.json ← back@$ref ($(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["info"]["version"]' "$here/TogetherTests/Resources/openapi.json"))"
