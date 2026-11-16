#!/usr/bin/env bash
# pytest-shard.py: every test file lands in exactly one shard, shards are
# balanced by test count, and an empty shard is an error rather than an
# argument-less pytest (which would run the whole suite).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
shard="$here/../pytest-shard.py"
fail() { echo "FAIL: $*" >&2; exit 1; }

collected="$(
  for i in $(seq 1 40); do echo "etqan/big/tests/test_big.py::test_$i"; done
  for f in a b c d e f g h; do
    for i in $(seq 1 5); do echo "etqan/$f/tests/test_$f.py::test_${i}[param-${i}]"; done
  done
  echo "etqan/z/tests/test_z.py::TestClass::test_method"
  echo
  echo "81 tests collected in 0.42s"
)"

all=""
for i in 1 2 3; do
  out="$(python3 "$shard" "$i" 3 <<<"$collected")"
  [ -n "$out" ] || fail "shard $i is empty"
  all+="$out"$'\n'
  # Shard 1 takes the 40-test file alone; the 41 small ones split 20/21.
  n="$(grep -c . <<<"$out")"
  case "$i" in
    1) [ "$out" = "etqan/big/tests/test_big.py" ] || fail "shard 1 is '$out'" ;;
    *) [ "$n" -ge 4 ] && [ "$n" -le 5 ] || fail "shard $i has $n files" ;;
  esac
done

expected="$(grep '::' <<<"$collected" | cut -d: -f1 | sort -u)"
[ "$(grep . <<<"$all" | sort)" = "$expected" ] || fail "files lost or duplicated"

# Same input, same answer: shards run on different runners.
[ "$(python3 "$shard" 2 3 <<<"$collected")" = "$(python3 "$shard" 2 3 <<<"$collected")" ] ||
  fail "not deterministic"

python3 "$shard" 5 3 <<<"$collected" >/dev/null 2>&1 && fail "shard 5 of 3 accepted"
python3 "$shard" 2 2 <<<"etqan/a/tests/test_a.py::test_1" >/dev/null 2>&1 &&
  fail "an empty shard was accepted"

echo "pytest_shard_test: OK"
