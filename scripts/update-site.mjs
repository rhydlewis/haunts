#!/usr/bin/env node
//
// update-site.mjs — stage a built release into the gethaunts.app SITE repo so
// Netlify can publish it. Called by scripts/release.sh; not run by hand.
//
// The DMG is hosted ON the site (committed under src/assets/dmg/, served by
// Netlify) — NOT on GitHub Releases. This script:
//   1. copies the DMG            → SITE/src/assets/dmg/<filename>
//   2. overwrites the appcast    → SITE/src/appcast.xml   (EdDSA-signed)
//   3. updates SITE/src/latest.json (version/build/filename/publishedAt/released)
//   4. upserts the SITE/src/_data/changes.json entry for this version
//
// It is idempotent on version: re-running for the same version updates the
// existing changelog entry's date rather than prepending a duplicate. If NOTES
// is empty and an entry already exists (e.g. v0.1's hand-written one), the
// existing changes are kept untouched.
//
// Env:
//   VERSION       (required)  semver, e.g. 0.1.0
//   BUILD         (required)  CFBundleVersion, e.g. 1
//   DMG_PATH      (required)  path to the built .dmg
//   APPCAST_PATH  (required)  path to the generated appcast.xml
//   SITE_PATH     (required)  path to the gethaunts.app repo
//   NOTES         (optional)  one change per line: "- type: description"
//   TITLE         (optional)  changelog entry title (default: derived)
//   PUBLISHED_AT  (optional)  ISO timestamp (default: now)
//
// Refs: bead z-for-finder-ge2

import { readFileSync, writeFileSync, copyFileSync, mkdirSync } from "node:fs";
import { join, basename } from "node:path";

const env = (k, required = true) => {
  const v = process.env[k];
  if (required && (v === undefined || v === "")) {
    console.error(`update-site: missing required env ${k}`);
    process.exit(1);
  }
  return v;
};

const VERSION = env("VERSION");
const BUILD = env("BUILD");
const DMG_PATH = env("DMG_PATH");
const APPCAST_PATH = env("APPCAST_PATH");
const SITE_PATH = env("SITE_PATH");
const NOTES = process.env.NOTES || "";
const TITLE = process.env.TITLE || "";
const PUBLISHED_AT = process.env.PUBLISHED_AT || new Date().toISOString();

const filename = basename(DMG_PATH);

// --- paths in the site repo ------------------------------------------------
const dmgDir = join(SITE_PATH, "src", "assets", "dmg");
const dmgDest = join(dmgDir, filename);
const appcastDest = join(SITE_PATH, "src", "appcast.xml");
const latestPath = join(SITE_PATH, "src", "latest.json");
const changesPath = join(SITE_PATH, "src", "_data", "changes.json");

// --- 1. copy the DMG -------------------------------------------------------
mkdirSync(dmgDir, { recursive: true });
copyFileSync(DMG_PATH, dmgDest);
console.log(`✓ DMG     → src/assets/dmg/${filename}`);

// --- 2. overwrite the appcast ----------------------------------------------
copyFileSync(APPCAST_PATH, appcastDest);
console.log(`✓ appcast → src/appcast.xml`);

// --- 3. latest.json --------------------------------------------------------
const latest = JSON.parse(readFileSync(latestPath, "utf8"));
latest.version = VERSION;
latest.build = Number.isNaN(Number(BUILD)) ? BUILD : Number(BUILD);
latest.filename = filename;
latest.publishedAt = PUBLISHED_AT;
latest.released = true;
writeFileSync(latestPath, JSON.stringify(latest, null, 2) + "\n");
console.log(`✓ latest.json → v${VERSION} (build ${BUILD}), released:true`);

// --- 4. changes.json (upsert by version) -----------------------------------
function parseNotes(raw) {
  return raw
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("- "))
    .map((l) => {
      const body = l.slice(2);
      const i = body.indexOf(":");
      if (i === -1) return { type: "improvement", description: body.trim() };
      return {
        type: body.slice(0, i).trim().toLowerCase(),
        description: body.slice(i + 1).trim(),
      };
    });
}

const changes = JSON.parse(readFileSync(changesPath, "utf8"));
const isoDate = PUBLISHED_AT.split("T")[0];
const existingIdx = changes.findIndex((e) => e.version === VERSION);
const parsed = parseNotes(NOTES);

if (existingIdx !== -1) {
  // Update date; refresh changes only if new NOTES were supplied.
  const entry = changes[existingIdx];
  entry.date = isoDate;
  entry.build = String(BUILD);
  if (parsed.length > 0) {
    entry.changes = parsed;
    if (TITLE) entry.title = TITLE;
  }
  console.log(
    `✓ changes.json → updated existing v${VERSION} entry (date ${isoDate}${
      parsed.length ? ", changes refreshed" : ", changes kept"
    })`
  );
} else {
  if (parsed.length === 0) {
    console.error(
      `update-site: no changes.json entry for v${VERSION} and no NOTES given — supply --notes`
    );
    process.exit(1);
  }
  const title = TITLE || parsed.map((c) => c.description).join("; ");
  changes.unshift({
    version: VERSION,
    build: String(BUILD),
    date: isoDate,
    title,
    description: title,
    changes: parsed,
  });
  console.log(`✓ changes.json → prepended new v${VERSION} entry`);
}

writeFileSync(changesPath, JSON.stringify(changes, null, 2) + "\n");
