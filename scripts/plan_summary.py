"""Turns a plan's JSON into a short Markdown summary for the CI job page.

The repo is public, so CI never prints the raw plan: it's full of ARNs with
the account ID in them. This lists only resource addresses and what would
happen to each.
"""
import json
import sys
from collections import Counter

plan = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "plan.json"))
rows, counts = [], Counter()
for r in plan.get("resource_changes", []):
    change = r["change"]
    action = "+".join(a for a in change["actions"] if a != "no-op") or None
    if change.get("importing"):
        action = f"import{'+' + action if action else ''}"
    if action:
        rows.append((r["address"], action))
        counts[action] += 1

if not rows:
    print("### No changes\nThe account matches the code.")
else:
    print("### Planned changes\n")
    print(", ".join(f"**{n}** {a}" for a, n in sorted(counts.items())) + "\n")
    print("| Resource | Action |\n|---|---|")
    for address, action in rows:
        print(f"| `{address}` | {action} |")
