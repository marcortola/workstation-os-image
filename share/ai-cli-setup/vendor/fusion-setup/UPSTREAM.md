# Vendored: opencode-fusion `fusion-setup` skill

Source: https://github.com/mihneaptu/opencode-fusion (`.opencode/skills/fusion-setup`)

Vendored secret-free so `install.sh` can run the deterministic installer
(`scripts/install.js`) offline with a chosen subscription profile. Refresh with:

    npx skills add mihneaptu/opencode-fusion --skill fusion-setup -g -a opencode -y
    cp -a ~/.agents/skills/fusion-setup <this-dir>

Contains only static prompt/profile/plugin files and the Node installer — no
credentials. `install.js` never stores keys; provider auth is via `opencode
auth login`.
