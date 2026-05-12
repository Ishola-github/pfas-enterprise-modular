# External blind — raw data

Place **independent** PFAS datasets here (CSV, Excel, etc.). Large files are typically **gitignored**; record **SHA-256** and download metadata in **`../results/EXTERNAL_BLIND_RESULTS_v1.md`** or a small **`MANIFEST.txt`** in this folder.

## Minimum documentation per file

- Original **source title** and **URL**
- **Download date** (UTC or local, state which)
- **License / use restrictions**
- **File hash** (SHA-256)

Do not use this folder for data that was already used to **train**, **tune τ**, or **select features** for the frozen model.
