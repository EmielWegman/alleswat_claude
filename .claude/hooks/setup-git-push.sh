#!/usr/bin/env bash
# Configureer git zodat `git push` naar GitHub werkt in Claude Code web-sessies.
#
# Achtergrond: de standaard git-proxy in web-sessies heeft geen schrijfrechten
# (push faalt met HTTP 403). Daarom routeren we pushes rechtstreeks naar
# github.com en authenticeren we met het GH_TOKEN uit de omgeving.
#
# Het token wordt NIET op schijf opgeslagen: een credential helper leest het
# live uit de omgeving op het moment dat git pusht. Fetch/pull blijven via de
# proxy-origin lopen, zodat het read-gedrag van de harness ongewijzigd blijft.
#
# Draait bij elke sessiestart (SessionStart-hook); de container is ephemeral,
# dus de git-config wordt elke sessie opnieuw gezet.
set -euo pipefail

# Niets te doen zonder token of buiten een git-repo.
[ -n "${GH_TOKEN:-}" ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

origin="$(git config --get remote.origin.url 2>/dev/null || true)"
[ -n "$origin" ] || exit 0

# Leid <owner>/<repo> af uit de proxy-URL (…/git/<owner>/<repo>) of een gewone
# github-URL. Bij een onbekend patroon laten we de config met rust.
repo="$(printf '%s' "$origin" | sed -E 's#^.*[:/]git/##; s#^.*github\.com[:/]##; s#\.git$##')"
case "$repo" in
  */*) : ;;        # ziet eruit als owner/repo
  *) exit 0 ;;     # niet-herkende remote
esac

# Env-gebaseerde credential helper, alleen voor github.com: geeft het token uit
# de omgeving terug op het moment van pushen. Er wordt geen secret in een
# git-config-bestand bewaard ($GH_TOKEN blijft letterlijk staan en wordt pas
# door de shell van git geëxpandeerd tijdens de push).
git config --global credential."https://github.com".helper \
  '!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f'

# Stuur pushes rechtstreeks naar github.com; fetch/pull houden de proxy-origin.
git config remote.origin.pushurl "https://github.com/${repo}.git"

echo "git push naar https://github.com/${repo}.git geconfigureerd via GH_TOKEN"
