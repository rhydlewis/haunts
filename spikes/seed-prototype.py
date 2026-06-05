#!/usr/bin/env python3
"""
Spike 3b — z-for-finder DAY-ONE WARM-SEEDING prototype (throwaway).

The wedge is "warm on first launch, zero setup". This proves we can build a
good frecency list from signals that ALREADY EXIST before the app observes
anything — and shows WHICH independent sources agree on each folder (the
agreement is the confidence story incumbents can't tell, because they start cold).

Sources blended (whatever is present on the machine):
  * git repos under ~/code         -> active project roots, weighted by .git recency
  * fish/zsh shell history          -> dirs you actually cd into / reference
  * JetBrains recentProjects.xml    -> explicit "projects I open in an IDE"
  * Sublime session                 -> open folders / recent files
  * Spotlight metadata (mdfind)     -> recency x use-count (Spikes 1-2 signal)

Everything rolls up to the nearest .git root. Run: python3 spikes/seed-prototype.py
"""
import os, re, glob, time, json, subprocess, html
from collections import defaultdict
from xml.etree import ElementTree as ET

HOME = os.path.expanduser("~")
NOW = time.time()
HALFLIFE_D = 30.0
def decay(age_days): return 0.5 ** (max(0, age_days) / HALFLIFE_D)
def age_days(ts): return (NOW - ts) / 86400.0

# ---- discover git repos (for rollup + as a seed) -------------------------
REPOS = set()
def scan_repos(root, max_depth):
    base = root.rstrip("/").count("/")
    for dirpath, dirs, _ in os.walk(root):
        depth = dirpath.count("/") - base
        if depth >= max_depth:
            dirs[:] = []
        dirs[:] = [d for d in dirs if (d not in
                   ("Library","node_modules",".Trash","Pictures","Movies") and not d.startswith(".")) or d==".dotfiles"]
        if os.path.isdir(os.path.join(dirpath, ".git")):
            REPOS.add(dirpath); dirs[:] = []   # don't descend into a repo
scan_repos(os.path.join(HOME, "code"), 5)
scan_repos(HOME, 2)

def git_root(path):
    cur = path
    while cur.startswith(HOME) and cur not in ("/", HOME):
        if cur in REPOS or os.path.isdir(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    return path

# ---- score accumulator: folder -> {source: weight} -----------------------
scores = defaultdict(lambda: defaultdict(float))
JUNK = {"Library", "Pictures", "Movies", ".Trash"}
def add(path, source, weight):
    if not path: return
    path = os.path.realpath(os.path.expanduser(path))
    if not os.path.isdir(path):
        path = os.path.dirname(path)
    if (not path.startswith(HOME) or "/Library/" in path or path.endswith("/Library")
            or path == HOME or os.path.basename(path) in JUNK):
        return
    scores[git_root(path)][source] += weight

# ---- 1. git repos: weight by recency of .git activity --------------------
for repo in REPOS:
    head = os.path.join(repo, ".git", "HEAD")
    idx  = os.path.join(repo, ".git", "index")
    mt = max([os.path.getmtime(p) for p in (head, idx) if os.path.exists(p)] or [os.path.getmtime(repo)])
    add(repo, "git", decay(age_days(mt)))

# ---- 2. shell history (fish primary, zsh fallback) -----------------------
def harvest_paths_from_text(cmd):
    out = []
    m = re.match(r"\s*(?:cd|z|j|pushd)\s+(.+)", cmd)
    if m: out.append(m.group(1).strip().strip('"\''))
    for tok in re.findall(r"(~?/[^\s'\"|;&]+)", cmd):
        out.append(tok)
    return out

fish = os.path.join(HOME, ".local/share/fish/fish_history")
if os.path.exists(fish):
    cur_when = NOW
    with open(fish, errors="ignore") as f:
        for line in f:
            mw = re.match(r"\s+when:\s+(\d+)", line)
            if mw: cur_when = int(mw.group(1)); continue
            mc = re.match(r"- cmd:\s+(.*)", line)
            mp = re.match(r"\s+- (.+)", line)  # paths: list entries
            for raw in (harvest_paths_from_text(mc.group(1)) if mc else
                        ([mp.group(1)] if mp else [])):
                add(raw, "shell", 0.8 * decay(age_days(cur_when)))

zsh = os.path.join(HOME, ".zsh_history")
if os.path.exists(zsh):
    with open(zsh, errors="ignore") as f:
        for line in f:
            cmd = re.sub(r"^: \d+:\d+;", "", line.rstrip())
            for raw in harvest_paths_from_text(cmd):
                add(raw, "shell", 0.5)   # no reliable per-line timestamp here

# ---- 3. JetBrains recent projects ----------------------------------------
for xmlf in glob.glob(os.path.join(HOME, "Library/Application Support/JetBrains/*/options/recentProjects.xml")):
    try:
        root = ET.parse(xmlf).getroot()
    except Exception:
        continue
    for entry in root.iter("entry"):
        key = entry.get("key")
        if not key: continue
        path = key.replace("$USER_HOME$", HOME).replace("$APPLICATION_HOME_DIR$", "")
        ts = None
        meta = entry.find(".//RecentProjectMetaInfo")
        for opt in entry.iter("option"):
            if opt.get("name") in ("projectOpenTimestamp", "activationTimestamp"):
                try: ts = int(opt.get("value")) / 1000.0
                except: pass
        add(path, "jetbrains", 1.0 * (decay(age_days(ts)) if ts else 0.5))

# ---- 4. Sublime session --------------------------------------------------
for sess in glob.glob(os.path.join(HOME, "Library/Application Support/Sublime Text*/Local/Session.sublime_session")):
    try:
        data = json.load(open(sess, errors="ignore"))
    except Exception:
        continue
    for p in data.get("folder_history", []):
        add(p, "sublime", 0.7)
    for win in data.get("windows", []):
        for folder in win.get("folders", []):
            add(folder.get("path"), "sublime", 0.9)

# ---- 5. Spotlight metadata recency x use-count (Spikes 1-2) ---------------
try:
    out = subprocess.run(
        ["mdfind", "kMDItemLastUsedDate >= $time.now(-7776000)", "-onlyin", HOME],
        capture_output=True, text=True, timeout=20).stdout
    for path in out.splitlines():
        d = os.path.dirname(path)
        if "/Library/" in d or "/." in d: continue
        add(d, "meta", 0.9)   # flat weight here; Spike 2 already proved the richer version
except Exception as e:
    print("  (metadata source skipped:", e, ")")

# ---- blend & rank --------------------------------------------------------
# Per-source normalization: each source contributes at most its trust weight,
# so no single high-volume source (e.g. today's shell history) can dominate.
SRC_ORDER = ["git", "jetbrains", "shell", "sublime", "meta"]
TRUST = {"git": 1.0, "jetbrains": 1.0, "shell": 1.0, "sublime": 0.8, "meta": 1.0}
TRANSIENT = [os.path.join(HOME, d) for d in ("Downloads", "Desktop", "Screenshots")]
src_max = defaultdict(float)
for srcs in scores.values():
    for s, v in srcs.items():
        src_max[s] = max(src_max[s], v)

blended = []
for folder, srcs in scores.items():
    total = sum((srcs[s] / src_max[s]) * TRUST.get(s, 1.0) for s in srcs if src_max[s])
    if any(folder == p or folder.startswith(p + "/") for p in TRANSIENT):
        total *= 0.08
    blended.append((total, folder, srcs))
blended.sort(reverse=True)

def tag(srcs):
    return "".join(("●" if s in srcs else "·") for s in SRC_ORDER)

print(f"\n  DAY-ONE WARM LIST — blended from {len([s for s in ['git','shell','jetbrains','sublime','meta']])} signal types, zero prior observation")
print(f"  sources: {' '.join(f'{i+1}={s}' for i,s in enumerate(SRC_ORDER))}   (● = source voted for this folder)\n")
print(f"  {'rank':>4}  {'score':>6}  {'git/jb/sh/sub/meta':<18}  folder")
top = blended[:25]
for i, (total, folder, srcs) in enumerate(top, 1):
    disp = folder.replace(HOME, "~")
    print(f"  {i:>4}  {total:6.2f}  {tag(srcs):<18}  {disp}")

multi = sum(1 for _, _, s in top if len(s) >= 2)
print(f"\n  {len(scores)} candidate folders from {len(REPOS)} git repos + shell + IDE + metadata.")
print(f"  CONFIDENCE: {multi}/{len(top)} of the top {len(top)} are confirmed by >=2 independent sources.")
print( "  (Cross-source agreement on day one is the thing a cold-starting incumbent cannot show.)")
