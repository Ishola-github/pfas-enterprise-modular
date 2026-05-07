# One canonical Git repo for PFAS (toxicology + enterprise)

**Canonical project:** this tree — `pfas-toxicology` (Shiny, NHANES, hybrid encoder, Gradle, EPA downloads, UCMR pipeline).

**`pfas-enterprise-modular`:** treat as a **spike / precursor** for UCMR labeling; its UCMR scripts and `data/config` / bridge layout are already **copied in here**. You can retire the old folder or keep it read-only for reference.

---

## 1. Fix Git if `.git` lives in the wrong place

If `git status` from **inside** `pfas-toxicology` shows your whole user profile or `Downloads`, the repository root is wrong.

**Do this once:**

1. Find where `.git` actually is: from `pfas-toxicology` run  
   `git rev-parse --show-toplevel`  
   It should print **this folder** (the directory that contains `LatestPFAS.R` and `scripts/`).

2. If toplevel is **not** this folder, either:
   - **Option A:** Rename/remove the stray `.git` at the wrong level only if you are sure nothing important was committed there (backup first), then:
     ```powershell
     cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
     git init
     git add .
     git commit -m "Initial commit: PFAS toxicology canonical repo"
     ```
   - **Option B:** Ask someone with Git experience to **split** history so only `pfas-toxicology/` is preserved (filter-repo / subtree).

Afterward, `git rev-parse --show-toplevel` from the app root must equal that path.

---

## 2. Make GitHub (or GitLab) use only toxicology

1. Create **one** remote repo (e.g. `pfas-toxicology` or `pfas-enterprise`).
2. From the **canonical** folder:

   ```powershell
   cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
   git remote add origin https://github.com/<you>/<repo>.git
   git branch -M main
   git push -u origin main
   ```

3. Archive or delete the old `pfas-enterprise-modular` remote if you no longer need a second codebase.

---

## 3. Optional: one-time import of enterprise **history** (advanced)

Only if you need **merged Git history** from `pfas-enterprise-modular` into this repo:

```powershell
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
git remote add enterprise /path/to/pfas-enterprise-modular   # or HTTPS
git fetch enterprise
git merge enterprise/main --allow-unrelated-histories
# Resolve conflicts; delete enterprise remote when done: git remote remove enterprise
```

Alternatively use **`git subtree add`** if enterprise lived in a subdirectory of a monorepo (not the case by default).

Most teams **do not** need this if the UCMR files were already copied in; a single commit “Align UCMR pipeline with enterprise” is enough.

---

## 4. What stays in sync

| Piece | Location |
|-------|----------|
| UCMR exceedance build | `scripts/build_ucmr_exceedance_dataset.py` |
| R launcher | `scripts/run_ucmr_dataset_pipeline.R` |
| Limits | `data/config/ucmr_analyte_limits_ngl.csv` |
| Bridge | `data/external/comptox/pfasmaster_bridge.csv` (and `compontox/` template) |
| Outputs | `data/training/ucmr_exceedance_labeled.csv` (large file; usually gitignored) |

When updating from another machine, copy those paths or pull from **this** remote only.

---

## 5. RStudio / OneDrive copies

Use **git clone** or sync **this** repo into `PFAS on R Studio`; avoid maintaining a third divergent tree. If you must use OneDrive, keep **one** folder that is `git pull` / `git push` clean.
