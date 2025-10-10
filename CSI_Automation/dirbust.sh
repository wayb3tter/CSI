#!/usr/bin/env bash
# simple-dirb-case.sh
# Small directory buster that uses a case switch for arguments.
# Usage:
#   ./simple-dirb-case.sh -u TARGET_URL -w WORDLIST [-e ext1,ext2] [-h]
#
# Depth is fixed to 2 (root -> level1 -> level2).
# Requires: curl

TARGET=""
WORDLIST=""
EXTS="php,html,htm,txt,bak"

show_help() {
  cat <<EOF
Requirements: curl [sudo apt install curl]

Usage: $0 -u TARGET_URL -w WORDLIST [-e ext1,ext2] [-h]

 -u TARGET_URL   base URL (e.g. https://example.com)
 -w WORDLIST     wordlist file (one word per line)
 -e ext1,ext2    optional comma-separated extensions (default: $EXTS)
 -h              show this help
EOF
}

# parse args with a switch (case)
while [ $# -gt 0 ]; do
  case "$1" in
    -u)
      TARGET="$2"; shift 2 ;;
    -w)
      WORDLIST="$2"; shift 2 ;;
    -e)
      EXTS="$2"; shift 2 ;;
    -h|--help)
      show_help; exit 0 ;;
    *)
      echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

if [ -z "$TARGET" ] || [ -z "$WORDLIST" ]; then
  echo "Error: target and wordlist are required."
  show_help
  exit 1
fi

if [ ! -f "$WORDLIST" ]; then
  echo "Wordlist not found: $WORDLIST"
  exit 2
fi

TARGET="${TARGET%/}"   # remove trailing slash
IFS=',' read -r -a EXTS_ARR <<< "$EXTS"
mapfile -t WORDS < <(sed -e 's/^\s*//;s/\s*$//' -e '/^\s*$/d' -e '/^\s*#/d' "$WORDLIST")

check_url() {
  url="$1"
  code=$(curl -sS -I --max-time 6 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  if [ "$code" = "000" ]; then
    code=$(curl -sS --max-time 6 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  fi
  case "$code" in
    200|301|302|401|403|5??) echo "[$code] $url" ;;
  esac
}

scan_level() {
  bases=("$@")
  next=()
  for base in "${bases[@]}"; do
    for w in "${WORDS[@]}"; do
      w="${w// /}"
      [ -z "$w" ] && continue
      u="$base/$w"
      check_url "$u"
      for ext in "${EXTS_ARR[@]}"; do
        [ -z "$ext" ] && continue
        check_url "$u.$ext"
      done
      dir="$base/$w/"
      code=$(curl -sS -I --max-time 4 -o /dev/null -w "%{http_code}" "$dir" 2>/dev/null || echo "000")
      case "${code:0:1}" in
        2|3|4) next+=("${base%/}/$w") ;;
      esac
    done
  done
  # unique
  printf "%s\n" "${next[@]}" | awk '!seen[$0]++ {print $0}'
}

echo "Target: $TARGET"
echo "Words: ${#WORDS[@]}  Exts: ${EXTS_ARR[*]}"
echo "Depth: 2"
echo

level0=("$TARGET")
level1=( $(scan_level "${level0[@]}") )

if [ "${#level1[@]}" -gt 0 ]; then
  scan_level "${level1[@]}" >/dev/null 2>&1 || true
fi

echo "Done."
exit 0
