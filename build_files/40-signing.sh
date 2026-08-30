#!/usr/bin/bash
# Require a valid signature on our own images.
#
# base-main ships a policy.json that is deny-by-default and already trusts
# ghcr.io/ublue-os. We MERGE into it rather than replacing it: dropping the
# ublue entry would leave the machine unable to pull its own base.
set -ouex pipefail

policy=/etc/containers/policy.json
key=/etc/pki/containers/marcortola.pub

test -f "$policy" || { echo "no policy.json to extend" >&2; exit 1; }
test -f "$key"    || { echo "signing pubkey missing: $key" >&2; exit 1; }

tmp="$(mktemp)"
jq --arg key "$key" '
    .transports.docker["ghcr.io/marcortola"] = [{
        type: "sigstoreSigned",
        keyPath: $key,
        signedIdentity: { type: "matchRepository" }
    }]
' "$policy" > "$tmp"

# Never ship a policy we cannot parse: a broken policy.json means the machine
# can pull nothing at all, including a rollback.
jq -e '
    (.default[0].type == "reject")
    and (.transports.docker | has("ghcr.io/marcortola"))
    and (.transports.docker | has("ghcr.io/ublue-os"))
' "$tmp" >/dev/null

install -m 0644 "$tmp" "$policy"
rm -f "$tmp"
