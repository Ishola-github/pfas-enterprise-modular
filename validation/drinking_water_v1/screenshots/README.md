# Validation screenshots (frozen evidence)

This folder is the correct destination for **visual** validation evidence. Reference these files from `runs/<run_id>/manifest.json` under `artifacts.app_screenshots_uris` (paths or URIs).

## What to include

- PFAS ML results screen  
- Holdout metrics screen  
- Successful training screen  
- UCMR pipeline success screen  
- Artifact verification screen  
- Any important validation or error-handling screenshots  

## How to add files (Windows)

### Drag and drop

1. Open another **File Explorer** window.  
2. Go to where images are saved, for example:
   - `Pictures\Screenshots`
   - or **Downloads** / **Desktop**
3. Select the screenshot files.  
4. **Drag** them into this `screenshots` folder window.  
5. **Release** the mouse button.

### Copy and paste

1. Select the screenshots in their current folder.  
2. **Ctrl+C**  
3. Click inside this `screenshots` folder.  
4. **Ctrl+V**

## Expected contents

After copying you should see **`.gitkeep`** (keeps the folder in git when empty) plus your **PNG** or **JPG** files. Those images are part of the **frozen validation evidence** package for the declared freeze (see `../reports/FREEZE_v1.md`).
