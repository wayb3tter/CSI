#!/usr/bin/env bash
# Usage: ./linuxprivesc.sh [--full] [-h]
#  --full   show more lines for lists (longer output)
#  -h       help

set -o pipefail

FULL=0
for a in "$@"; do
  case "$a" in
    --full) FULL=1 ;;
    -h|--help) 
      cat <<EOF
Usage: $0 [--full] [-h]
 --full    show larger lists (more lines)
 -h        show this help
EOF
      exit 0
      ;;
    *) ;;
  esac
done

# limits (small by default)
if [ "$FULL" -eq 1 ]; then
  L1=200
  L2=200
else
  L1=30   # primary lists (SUID, world-writable, etc.)
  L2=6    # short lists (hidden files, configs)
fi

# prune common noisy mounts
FIND_PRUNE=(-path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -path /run -prune -o -path /var/lib -prune -o)

printf "\n== linuxprivesc: concise local privesc checks ==\n\n"

# 1) UID, username, id, gid and other ids
printf "[01] Identity: user & ids\n"
printf "  user: %s (uid=%s)\n" "$(whoami 2>/dev/null || echo unknown)" "$(id -u 2>/dev/null || echo unknown)"
printf "  groups: %s\n" "$(id -nG 2>/dev/null || echo unknown)"
printf "  ids: %s\n" "$(id 2>/dev/null || echo unknown)"
printf "\n"

# 2) SUID permissions and list them (use requested find syntax pruned)
printf "[02] SUID files (perm -u=s) — showing up to %s entries\n" "$L1"
# use -ls-like output but pruned from noisy FS
find / "${FIND_PRUNE[@]}" -perm -u=s -type f -printf '%M %u:%g %p\n' 2>/dev/null | sort | uniq | head -n "$L1" | sed 's/^/  /'
printf "\n"

# 3) Sudo version
printf "[03] sudo version (if installed)\n"
if command -v sudo >/dev/null 2>&1; then
  sudo --version 2>/dev/null | sed -n '1,2p' | sed 's/^/  /'
else
  printf "  sudo: not installed\n"
fi
printf "\n"

# 4) Kernel version
printf "[04] Kernel version\n"
printf "  %s\n" "$(uname -srmo 2>/dev/null || uname -sr)"
printf "\n"

# 5) sudo -l output (what current user can run)
printf "[05] sudo -l (may prompt for password) — concise\n"
if command -v sudo >/dev/null 2>&1; then
  # show sudo -l but limit lines for brevity
  sudo -l 2>&1 | sed 's/^/  /' | head -n "$L1"
else
  printf "  sudo: not installed\n"
fi
printf "\n"

# 6) World-writable files except /tmp
printf "[06] World-writable files/dirs (excludes /tmp) — showing up to %s entries\n" "$L1"
# exclude /tmp specifically; prune noisy FS
find / -path /tmp -prune -o "${FIND_PRUNE[@]}" -type d -perm -0002 -printf '  DIR %M %u:%g %p\n' -o -type f -perm -0002 -printf '  FILE %M %u:%g %p\n' 2>/dev/null \
  | sed '/^  /!d' | head -n "$L1"
printf "\n"

# 7) Hidden files except common files in /  (concise)
# Interpretation: list dotfiles under top-level directories (depth 1 or 2), excluding well-known root system items.
printf "[07] Hidden files (dotfiles) near / — concise\n"
# exclude a few common system paths and common dotfiles that are expected
EXCLUDE_PATTERNS="*/.cache/* */.local/* */.config/*"
find /* -maxdepth 2 -mindepth 1 \( -name ".*" -type f -o -name ".*" -type d \) 2>/dev/null \
  | grep -vE '/(proc|sys|dev|run|var|boot|lib|usr|tmp|srv|opt)/' \
  | grep -vE "$EXCLUDE_PATTERNS" \
  | head -n "$L2" \
  | sed 's/^/  /' || true
printf "  (use --full to show more)\n\n"

# 8) Internal network state (netstat -antup)
printf "[08] Network listening/connections (netstat -antup / ss -antup fallback) — concise\n"
if command -v netstat >/dev/null 2>&1; then
  netstat -antup 2>/dev/null | sed -n '1,80p' | sed 's/^/  /'
elif command -v ss >/dev/null 2>&1; then
  ss -antup 2>/dev/null | sed -n '1,80p' | sed 's/^/  /'
else
  printf "  netstat/ss: not available\n"
fi
printf "\n"

# 9) Password files
printf "[09] Password-related files & readability\n"
printf "  /etc/passwd: %s\n" "$( [ -r /etc/passwd ] && echo readable || echo not_readable )"
printf "  /etc/shadow: %s\n" "$( [ -r /etc/shadow ] && echo readable || echo not_readable )"
# quick search for files named *passwd* or *shadow* in /home (concise)
find /home /root -maxdepth 3 -type f \( -iname '*pass*' -o -iname '*shadow*' \) 2>/dev/null | head -n "$L2" | sed 's/^/  /' || true
printf "\n"

# 10) Configuration files (concise)
printf "[10] Common configuration files under /etc (showing top matches)\n"
# list readable .conf and prominent /etc subdirs
find /etc -maxdepth 2 -type f \( -iname '*.conf' -o -iname '*.cnf' -o -iname '*.ini' \) -printf '  %p\n' 2>/dev/null | head -n "$L1"
# also show /etc/hosts and /etc/ssh/sshd_config if present
[ -r /etc/hosts ] && printf '  /etc/hosts: readable\n'
[ -r /etc/ssh/sshd_config ] && printf '  /etc/ssh/sshd_config: readable\n'
printf "\n"

# 11) Writable binaries (in common bin dirs) — concise
printf "[11] Writable binaries in common binary dirs (user-writable or world-writable)\n"
BIN_DIRS=(/usr/bin /usr/local/bin /bin /sbin /usr/sbin)
for d in "${BIN_DIRS[@]}"; do
  [ -d "$d" ] || continue
  # show files that are writable by current user OR world-writable
  find "$d" -maxdepth 1 -type f \( -writable -o -perm -0002 \) -printf '  %M %u:%g %p\n' 2>/dev/null | head -n "$L2"
done
printf "\n"

printf "== done (concise). Use --full for more lines per section. ==\n\n"
exit 0
