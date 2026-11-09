# Sourced by the scripts (". .../compat.sh"): small helpers they share.

# sed_inplace SED-ARGUMENTS... FILE: edit a file in place, keeping the file itself (its permissions, a symlink to
# it). Fails, and leaves the file alone, if sed fails.
sed_inplace() {
  _f=$(eval "printf '%s' \"\${$#}\"")
  _n=$(($# - 1))
  _args=""
  _i=1
  while [ "$_i" -le "$_n" ]; do _args="$_args \"\${$_i}\""; _i=$((_i + 1)); done
  _t="$_f.i3dots-tmp.$$"
  if eval "sed $_args \"\$_f\"" >"$_t" 2>/dev/null; then
    cat "$_t" >"$_f" && rm -f "$_t"
  else
    rm -f "$_t"
    return 1
  fi
}

# pick_random: one line of standard input at random
pick_random() { awk -v s="$$" 'BEGIN { srand(); t = srand(); srand(s + t) } { a[NR] = $0 } END { if (NR) print a[int(rand() * NR) + 1] }'; }
