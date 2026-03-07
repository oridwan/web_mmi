#!/bin/bash
# 
# LEGO-xtal: AI-Assisted Rapid Crystal Structure Generation Towards a Target Local Environment
# 
# Authors: Osman Goni Ridwan, Sylvain Pitié, Monish Soundar Raj, Dong Dai, Gilles Frapper, 
#          Hongfei Xue, Qiang Zhu
# 
# Reference:
# @article{ridwan2025ai,
#   title={AI-Assisted Rapid Crystal Structure Generation Towards a Target Local Environment},
#   author={Ridwan, Osman Goni and Piti{\'e}, Sylvain and Raj, Monish Soundar and Dai, Dong and Frapper, Gilles and Xue, Hongfei and Zhu, Qiang},
#   journal={arXiv preprint arXiv:2506.08224},
#   year={2025}
# }
#
# Contact: oridwan@charlotte.edu, qzhu8@charlotte.edu
# Research Group: Materials Modelling and Informatics (MMI) / Zhu's Group
# PI: Qiang Zhu (Interim Director of BATT CAVE, Associate Professor)
#     Mechanical Engineering and Engineering Science
#     https://qzhu2017.github.io
#

set -e  # Exit immediately on error

# 1. Ensure jsmol assets exist (Render sometimes starts without them)
TARGET_LINK="ase_root/ase/db/static/jsmol"
mkdir -p "$(dirname "$TARGET_LINK")"

# If a bundled jsmol folder is present, prefer it
if [ -d "jsmol" ]; then
    if [ ! -e "$TARGET_LINK" ] && [ ! -L "$TARGET_LINK" ]; then
        echo "Linking bundled jsmol to $TARGET_LINK"
        ln -s "$PWD/jsmol" "$TARGET_LINK"
    elif [ -L "$TARGET_LINK" ]; then
        echo "Updating existing jsmol link..."
        rm -f "$TARGET_LINK"
        ln -s "$PWD/jsmol" "$TARGET_LINK"
    fi
else
    # Fallback: unzip from bundled Jmol archive if available
    if ls jmol-*/jsmol.zip >/dev/null 2>&1; then
        echo "Unzipping jsmol from bundled archive..."
        unzip jmol-*/jsmol.zip -d jsmol
        ln -s "$PWD/jsmol" "$TARGET_LINK"
    else
        echo "jsmol assets missing. Attempting to download latest minimal JSmol..."
        mkdir -p jsmol
        curl -L "https://sourceforge.net/projects/jmol/files/latest/download" -o /tmp/jmol-latest.tar.gz
        tar -xzf /tmp/jmol-latest.tar.gz -C /tmp && find /tmp -maxdepth 3 -name "jsmol.zip" -type f -print -quit | xargs -I {} cp {} /tmp/jsmol.zip 2>/dev/null || true
        if [ -f /tmp/jsmol.zip ]; then
            unzip /tmp/jsmol.zip -d jsmol
            ln -s "$PWD/jsmol" "$TARGET_LINK"
        else
            echo "WARNING: JSmol download failed; structure viewer will be unavailable." >&2
        fi
    fi
fi

# 2. Determine port (CLI arg > $PORT > default 5000)
if [ -n "$1" ]; then
    PORT="$1"
elif [ -z "$PORT" ]; then
    PORT=5010
fi
export PORT

# 3. Run the Flask app directly so we can set the port
echo "Starting ASE web server on port $PORT..."
export PYTHONPATH="$PWD/ase_root${PYTHONPATH:+:$PYTHONPATH}"
python3 - <<'PY'
import csv
import os
from pathlib import Path
from urllib.parse import urlencode

from flask import redirect, render_template, request, url_for

from ase.db.app import DBApp
from ase.db import connect

port = int(os.environ.get('PORT', '5000'))

app = DBApp()


def pick_existing_path(*candidates: str):
    for candidate in candidates:
        p = Path(candidate)
        if p.is_file():
            return p
    return None


def load_valid_structure_ids(csv_path: Path):
    ids = set()
    if not csv_path.is_file():
        return ids
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sid = (row.get("formula") or "").strip()
            if sid:
                ids.add(sid)
    return ids


class FilteredDatabase:
    """Filter to curated structure IDs and keep first occurrence only."""

    def __init__(self, db, valid_structure_ids):
        self.db = db
        self.valid_structure_ids = valid_structure_ids
        self.valid_rowids = set()
        seen = set()
        for row in self.db.select():
            sid = row.get("structure_id", f"row_{row.id}")
            if sid in self.valid_structure_ids and sid not in seen:
                self.valid_rowids.add(row.id)
                seen.add(sid)

    def select(self, *args, **kwargs):
        for row in self.db.select(*args, **kwargs):
            if row.id in self.valid_rowids:
                yield row

    def count(self, *args, **kwargs):
        if args or kwargs:
            return sum(1 for _ in self.select(*args, **kwargs))
        return len(self.valid_rowids)

    def get(self, *args, **kwargs):
        return self.db.get(*args, **kwargs)

    def __getattr__(self, name):
        return getattr(self.db, name)


db_projects = [
    {
        "slug": "carbon_sp2",
        "candidates": ("dbs/lego-sp2.db", "lego-sp2.db"),
    },
    {
        "slug": "electride_binary",
        "candidates": ("data/binary/final_electrides.db", "dbs/binay_electride_candidates.db"),
        "csv_candidates": ("data/binary/final_electrides.csv",),
    },
    {
        "slug": "electride_ternary",
        "candidates": ("data/ternary/final_electrides.db", "dbs/ternary_electride_candidates.db"),
        "csv_candidates": ("data/ternary/final_electrides.csv",),
    },
]

for entry in db_projects:
    slug = entry["slug"]
    db_path = pick_existing_path(*entry["candidates"])
    if db_path is None:
        print(f"[WARN] Could not find DB for '{slug}'. Tried: {', '.join(entry['candidates'])}")
        continue
    raw_db = connect(str(db_path))

    def set_electride_default_columns(project_slug: str):
        if project_slug not in ("electride_binary", "electride_ternary"):
            return
        project = app.projects.get(project_slug)
        if project is None:
            return
        # Match ElectrideFlow-style first view: show full formula, not reduced composition.
        project.default_columns = [
            "id",
            "formula",
            "space_group_number",
            "pearson_symbol",
            "dft_e_hull",
            "full_dft_e_hull",
            "mattersim_e_hull",
            "N_excess",
            "band_gap",
            "e0025",
            "e05",
            "e10",
            "band0",
            "band1",
            "electride",
        ]

    csv_candidates = entry.get("csv_candidates")
    if csv_candidates:
        csv_path_str = pick_existing_path(*csv_candidates)
        if csv_path_str:
            valid_ids = load_valid_structure_ids(Path(csv_path_str))
            if valid_ids:
                filtered_db = FilteredDatabase(raw_db, valid_ids)
                app.add_project(slug, filtered_db)
                set_electride_default_columns(slug)
                print(
                    f"[INFO] Loaded project '{slug}' from {db_path} "
                    f"(raw={raw_db.count()}, filtered={filtered_db.count()}, csv={csv_path_str})"
                )
                continue
            print(f"[WARN] CSV for '{slug}' found but empty: {csv_path_str}")
        else:
            print(f"[WARN] No CSV whitelist found for '{slug}'. Using raw DB rows.")

    app.add_project(slug, raw_db)
    set_electride_default_columns(slug)
    print(f"[INFO] Loaded project '{slug}' from {db_path} (rows={raw_db.count()})")

if not app.projects:
    raise SystemExit("No database files found. Expected at least one .db file.")

lab_projects = [
    {
        "slug": "carbon_sp2",
        "title": "LEGO-xtal sp2 Carbon Database",
        "href": "/carbon_sp2",
        "summary": "AI-assisted carbon crystal database with interactive structure browsing and query tools.",
        "status": "Active"
    },
    {
        "slug": "electride",
        "title": "Inorganic Electride Database",
        "href": "/electride",
        "summary": "ElectrideFlow datasets with binary and ternary systems, stability filters, and structure inspection.",
        "status": "Active"
    },
]


def redirect_with_query(target_endpoint: str, project_name: str):
    target = url_for(target_endpoint, project_name=project_name)
    query = request.args.get("query", "").strip()
    if query:
        target = f"{target}?{urlencode({'query': query})}"
    return redirect(target)


def lab_frontpage():
    return render_template("ase/db/templates/lab_home.html", projects=lab_projects)


app.flask.view_functions["frontpage"] = lab_frontpage


@app.flask.route("/electride")
@app.flask.route("/electride/")
def electride_default():
    return redirect_with_query("search", "electride_binary")


@app.flask.route("/electride/binary")
@app.flask.route("/electride/binary/")
def electride_binary_alias():
    return redirect_with_query("search", "electride_binary")


@app.flask.route("/electride/ternary")
@app.flask.route("/electride/ternary/")
def electride_ternary_alias():
    return redirect_with_query("search", "electride_ternary")


app.flask.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
PY
