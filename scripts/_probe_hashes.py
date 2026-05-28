import hashlib, pathlib
root = pathlib.Path('.')
files = [
    'data/external/nhanes_serum_h/PFAS_H.XPT',
    'data/external/nhanes_serum_h/SSPFAS_H.XPT',
    'data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv',
    'data/training/serum/nhanes_serum_pfas_2017_2018.csv',
    'data/training/serum/training.csv',
]
out = []
for f in files:
    p = root / f
    if p.is_file():
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        out.append(f"OK   sha256={h}  size={p.stat().st_size:>10}  {f}")
    else:
        out.append(f"MISS                                                                              {f}")
pathlib.Path('validation/serum_h_v1/.probe.txt').write_text('\n'.join(out) + '\n', encoding='ascii')
