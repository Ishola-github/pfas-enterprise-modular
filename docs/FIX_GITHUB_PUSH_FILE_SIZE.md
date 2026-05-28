# Fix: GitHub rejected push (file > 50 MB / 100 MB)

GitHub blocks blobs **> 100 MB**. **Do not commit** EPA UCMR `.txt` exports, full training matrices, or **`.terraform/`** provider plugins (often **hundreds of MB**).

## 1. Update `.gitignore`

Patterns are in this repo’s `.gitignore` (UCMR, `data/training/*`, `.terraform/`, `qc_datasets`, large uploads).  
Copy the same blocks into **`PFAS_on_R_Studio`** if that folder has its own `.gitignore`.

## 2. Stop tracking huge files (keep files on disk)

Run from **your** repo root (`PFAS_on_R_Studio` or `pfas-toxicology`), adjusting paths to match errors:

```powershell
# Terraform — always remove from Git
git rm -r --cached infra/shiny/.terraform 2>$null
git rm -r --cached .terraform 2>$null

# UCMR / training / QC (examples — add every path GitHub complained about)
git rm --cached UCMR5_533_clean.csv 2>$null
git rm --cached UCMR5_All.txt 2>$null
git rm --cached UCMR5_All_MA_WY.txt 2>$null
git rm --cached UCMR5_All_Tribes_AK_LA.txt 2>$null
git rm -r --cached data/external/epa_ucmr5/*.txt 2>$null
git rm --cached "data/external/qc_datasets/20260502_070533_pfas__1_.csv" 2>$null
git rm --cached data/processed/pfas_training_master.csv 2>$null
git rm --cached data/training/model_matrix_train.csv 2>$null
git rm --cached data/training/pfas_multisource_training.csv 2>$null
```

Then:

```powershell
git add .gitignore
git commit -m "Remove large data and terraform from Git tracking; expand gitignore"
git push -u origin main
```

## 3. If Git says “large files in earlier commits”

If those files were committed in **older** commits, one more commit is not enough — the big blobs stay in history.

**Easiest** (only if you have not shared this branch / team is OK losing history): reset to before the bad commit and recommit:

```powershell
git log --oneline   # find last good commit or empty
# Or: squash everything into one clean commit after fixing index
```

**Proper fix** (rewrite history): install [git-filter-repo](https://github.com/newren/git-filter-repo) and remove paths from all commits, **or** create a **new** repo with a fresh `git init` and one clean commit (no large files).

## 4. Optional: Git LFS

[LFS](https://git-lfs.com/) helps with large files **under team policy**, but it is **paid/limited** on GitHub for big projects. For UCMR and terraform, **gitignore + local/regenerate** is usually better than LFS.

## 5. Regenerate instead of committing

| Artifact | How to get it again |
|----------|---------------------|
| UCMR `.txt` | `download_epa_ucmr5.R` / EPA zip |
| `ucmr_exceedance_labeled.csv` | `build_ucmr_exceedance_dataset.py` / `run_ucmr_dataset_pipeline.R` |
| Training matrices | Your R/Python pipeline from smaller inputs |
