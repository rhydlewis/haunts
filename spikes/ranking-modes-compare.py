#!/usr/bin/env python3
"""
Compare three ranking blends on REAL data, to choose Session-2's merge behavior.

The three modes only differ once there's a VISIT history, so we synthesize a real
one from shell `cd` history (fish/zsh) — an honest record of where you navigate.

  A · Additive (balanced):    git + meta + decay(visitAge)*sqrt(visits)
  B · Visit-dominant (fork):  max( decay(visitAge)*sqrt(visits), git+meta ) + visits*0.1
  C · Pure frecency (z-like): decay(visitAge) * visits        (scan only discovers; visits rank)

Run: python3 spikes/ranking-modes-compare.py
"""
import os, re, glob, time, subprocess
from collections import defaultdict

HOME = os.path.expanduser("~")
NOW = time.time()
HALF = 30.0
def decay(age_days): return 0.5 ** (max(0.0, age_days) / HALF)
def age_days(ts): return (NOW - ts) / 86400.0

# ---- git repos (for rollup + git signal) ---------------------------------
REPOS = set()
def scan_repos(root, max_depth):
    base = root.rstrip("/").count("/")
    for dp, dirs, _ in os.walk(root):
        depth = dp.count("/") - base
        if depth >= max_depth: dirs[:] = []
        dirs[:] = [d for d in dirs if (d not in ("Library","node_modules","Pictures","Movies",".Trash")
                   and not d.startswith(".")) or d == ".dotfiles"]
        if os.path.isdir(os.path.join(dp, ".git")):
            REPOS.add(dp); dirs[:] = []
scan_repos(os.path.join(HOME, "code"), 5)
scan_repos(HOME, 2)

_rootcache = {}
def git_root(path):
    if path in _rootcache: return _rootcache[path]
    cur, root = path, path
    while cur.startswith(HOME) and cur not in ("/", HOME):
        if cur in REPOS: root = cur; break
        cur = os.path.dirname(cur)
    _rootcache[path] = root
    return root

def transient(p): return any(p == HOME+d or p.startswith(HOME+d+"/") for d in ("/Downloads","/Desktop","/Screenshots"))

# ---- discovered places: git + meta (additive freshScore) -----------------
fresh = defaultdict(float)
for repo in REPOS:
    head = os.path.join(repo, ".git", "HEAD"); idx = os.path.join(repo, ".git", "index")
    mt = max([os.path.getmtime(p) for p in (head, idx) if os.path.exists(p)] or [os.path.getmtime(repo)])
    fresh[repo] += decay(age_days(mt))
try:
    out = subprocess.run(["mdfind", "kMDItemLastUsedDate >= $time.now(-7776000)", "-onlyin", HOME],
                         capture_output=True, text=True, timeout=25).stdout
    for path in out.splitlines():
        d = os.path.dirname(path)
        if "/Library/" in d or "/." in d or not d.startswith(HOME) or d == HOME: continue
        root = git_root(d)
        w = 0.9
        if transient(root): w *= 0.08
        fresh[root] += w
except Exception as e:
    print("  (metadata skipped:", e, ")")

# ---- visit store from shell history (real navigation record) -------------
visits = defaultdict(int)      # folder -> count
last = defaultdict(float)      # folder -> latest timestamp
def add_visit(raw, when):
    p = os.path.realpath(os.path.expanduser(raw))
    if not os.path.isdir(p): return
    if not p.startswith(HOME) or "/Library/" in p or p == HOME: return
    root = git_root(p)
    visits[root] += 1
    last[root] = max(last[root], when)

def tokens(cmd):
    out = []
    m = re.match(r"\s*(?:cd|z|j|pushd)\s+(.+)", cmd)
    if m: out.append(m.group(1).strip().strip('"\''))
    out += re.findall(r"(~?/[^\s'\"|;&]+)", cmd)
    return out

fish = os.path.join(HOME, ".local/share/fish/fish_history")
if os.path.exists(fish):
    cur_when = NOW
    with open(fish, errors="ignore") as f:
        for line in f:
            mw = re.match(r"\s+when:\s+(\d+)", line)
            if mw: cur_when = int(mw.group(1)); continue
            mc = re.match(r"- cmd:\s+(.*)", line)
            mp = re.match(r"\s+- (.+)", line)
            for raw in (tokens(mc.group(1)) if mc else ([mp.group(1)] if mp else [])):
                add_visit(raw, cur_when)
zsh = os.path.join(HOME, ".zsh_history")
if os.path.exists(zsh):
    with open(zsh, errors="ignore") as f:
        for line in f:
            m = re.match(r": (\d+):\d+;(.*)", line)
            when = int(m.group(1)) if m else NOW - 86400*180
            cmd = m.group(2) if m else line
            for raw in tokens(cmd): add_visit(raw, when)

# ---- three rankings ------------------------------------------------------
folders = set(fresh) | set(visits)
def stored_signal(p):
    if visits[p] == 0: return 0.0
    return decay(age_days(last[p])) * (visits[p] ** 0.5)
def score_A(p): return fresh[p] + stored_signal(p)
def score_B(p): return max(stored_signal(p), fresh[p]) + visits[p]*0.1
def score_C(p): return decay(age_days(last[p])) * visits[p] if visits[p] else 0.0

def top(score, n=15):
    return sorted(folders, key=lambda p: -score(p))[:n]

def show(title, score):
    print(f"\n=== {title} ===")
    for i, p in enumerate(top(score), 1):
        d = p.replace(HOME, "~")
        tag = []
        if p in REPOS: tag.append("repo")
        if transient(p): tag.append("TRANSIENT")
        if visits[p]: tag.append(f"{visits[p]}visits")
        print(f"  {i:2d}  {score(p):6.2f}  {d}   [{' '.join(tag)}]")

print(f"\n{len(REPOS)} repos · {len(visits)} folders with shell-visit history · {len(folders)} candidates")
show("A · Additive (balanced)        git+meta + decay*sqrt(visits)", score_A)
show("B · Visit-dominant (fork mergePlaces)   max(visits,scan)+visits*0.1", score_B)
show("C · Pure frecency (z-like)     decay(age)*visits only", score_C)

# ---- where do they disagree? --------------------------------------------
a, b, c = [set(top(s)) for s in (score_A, score_B, score_C)]
print("\n--- disagreement in top-15 ---")
print("only in B (visit-dominant), not A:", sorted(x.replace(HOME,'~') for x in b - a) or "none")
print("only in C (pure-z), not A:        ", sorted(x.replace(HOME,'~') for x in c - a) or "none")
print("transient dirs surfaced — A:", sum(transient(x) for x in a),
      " B:", sum(transient(x) for x in b), " C:", sum(transient(x) for x in c))
