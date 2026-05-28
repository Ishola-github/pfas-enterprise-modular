# Controlled SOP masters (Word / PDF)

Place **QA-approved** full SOP suite files here for a consistent path in **`CONTROLLED_DOCUMENTS.md`**.

## Current markdown master (Rev 2.1)

```text
docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.md
```

Committed in git. Export to Word/PDF for QMS distribution:

```powershell
# Install once (if 'pandoc' is not recognized):
winget install --id JohnMacFarlane.Pandoc -e --accept-source-agreements --accept-package-agreements
# Close and reopen PowerShell, then:
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
pandoc "docs\sop\PFAS_Enterprise_5_SOP_Rev2.1.md" -o "docs\sop\PFAS_Enterprise_5_SOP_Rev2.1.docx"
```

Winget installs Pandoc under your user profile (not `C:\Program Files\Pandoc`). If PATH is stale:

```powershell
& "$env:LOCALAPPDATA\Pandoc\pandoc.exe" "docs\sop\PFAS_Enterprise_5_SOP_Rev2.1.md" -o "docs\sop\PFAS_Enterprise_5_SOP_Rev2.1.docx"
```

## Expected filename (Rev 1.0 Word example — superseded)

```text
PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx
```

Copy your completed Word export into:

```text
docs/sop/PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx
```

*(Adjust revision/date in the filename when you issue Rev 1.1, etc.)*

## Optional: markdown → Word (Pandoc)

If [Pandoc](https://pandoc.org/) is installed, from project root:

```powershell
pandoc "docs\SOP_INDEX.md" -o "docs\sop\PFAS_Enterprise_5_SOP_Index.docx"
```

Install on Windows (example): `winget install --id JohnMacFarlane.Pandoc` (or your org’s installer).

## Git

`*.docx` under `docs/sop/` is **gitignored** by default so large binaries are not committed accidentally. If your QMS requires version control of Word, use **Git LFS**, a **document repository**, or remove the ignore rule after policy review.

## RStudio quick open

From project root in PowerShell:

```powershell
cd "C:\Users\techj\OneDrive\Desktop\python_work\PFAS_on_R_Studio"
rstudio .
```

Then open **`docs/SOP_INDEX.md`** and **`validation/drinking_water_v1/reports/FREEZE_v1.md`**.
