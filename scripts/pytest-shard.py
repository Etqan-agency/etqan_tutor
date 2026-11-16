#!/usr/bin/env python3
"""Print the test files of one CI shard of the backend suite.

    pytest --collect-only -q | scripts/pytest-shard.py <index> <total>

Reads collected node ids on stdin and splits whole files (so module fixtures
are not set up twice) across <total> shards, largest file first onto the
lightest shard: deterministic, and balanced by test count. <index> is 1-based.
An empty shard is an error, never an empty argument list: pytest given no
files runs the whole suite.
"""

import sys
from collections import Counter


def shards(node_ids, total):
    counts = Counter(n.split("::", 1)[0] for n in node_ids if "::" in n)
    loads = [0] * total
    files = [[] for _ in range(total)]
    for path, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        i = loads.index(min(loads))
        loads[i] += n
        files[i].append(path)
    return [sorted(f) for f in files]


def main(argv):
    try:
        index, total = int(argv[1]), int(argv[2])
    except (IndexError, ValueError):
        sys.exit("usage: pytest-shard.py <index> <total>")
    if not 1 <= index <= total:
        sys.exit(f"shard {index} of {total} does not exist")
    mine = shards(sys.stdin.read().splitlines(), total)[index - 1]
    if not mine:
        sys.exit(f"shard {index} of {total} has no test files")
    print("\n".join(mine))


if __name__ == "__main__":
    main(sys.argv)
