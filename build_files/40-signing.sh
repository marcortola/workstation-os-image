#!/usr/bin/bash
# Require a valid signature on our own images.
#
# base-main ships a policy.json that is deny-by-default and already trusts
# ghcr.io/ublue-os. We MERGE into it rather than replacing it: dropping the
# ublue entry would leave the machine unable to pull its own base.
set -ouex pipefail

policy=/etc/containers/policy.json
key=/etc/pki/containers/workstation-signing.pub
# shellcheck source=/dev/null
source /usr/share/workstation-os-image/image.env
scope="ghcr.io/${REPO_ORGANIZATION}"

test -f "$policy" || { echo "no policy.json to extend" >&2; exit 1; }
test -f "$key"    || { echo "signing pubkey missing: $key" >&2; exit 1; }

# registries.d is generated rather than shipped: its only content is the
# owner-scoped key, so a static file would be one more place a fork must edit.
# Without it the signature is never fetched and policy.json has nothing to
# verify against -- a failure mode that looks like "signing works" until it
# doesn't.
install -d /etc/containers/registries.d
cat > /etc/containers/registries.d/workstation-signing.yaml <<EOF
docker:
  ${scope}:
    use-sigstore-attachments: true
EOF

tmp="$(mktemp)"
jq --arg key "$key" --arg scope "$scope" '
    .transports.docker[$scope] = [{
        type: "sigstoreSigned",
        keyPath: $key,
        signedIdentity: { type: "matchRepository" }
    }]
' "$policy" > "$tmp"

# Never ship a policy we cannot parse: a broken policy.json means the machine
# can pull nothing at all, including a rollback.
jq -e --arg scope "$scope" '
    (.default[0].type == "reject")
    and (.transports.docker | has($scope))
    and (.transports.docker | has("ghcr.io/ublue-os"))
' "$tmp" >/dev/null

install -m 0644 "$tmp" "$policy"
rm -f "$tmp"
