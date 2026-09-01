#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")" && pwd)

herdr_request() {
  printf '%s\n' "$1" | "$plugin_dir/herdr-request.sh"
}

even_width_splits() {
  jq -c '
    def columns:
      if .type == "pane" then 1
      elif .direction == "right" then (.first | columns) + (.second | columns)
      else 1
      end;
    def even_splits($path):
      if .type != "split" then empty
      else
        (if .direction == "right"
           then {path: $path, ratio: ((.first | columns) / columns)}
           else empty
         end),
        (.first | even_splits($path + [false])),
        (.second | even_splits($path + [true]))
      end;
    .result.layout.root | even_splits([])'
}

herdr_request '{"id":"export","method":"layout.export","params":{}}' |
  even_width_splits |
  while read -r split; do
    herdr_request "$(jq -cn --argjson split "$split" \
      '{id: "equalize", method: "layout.set_split_ratio", params: $split}')" >/dev/null
  done
