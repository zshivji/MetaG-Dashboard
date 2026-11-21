# MetaG-Dashboard
A dashboard to visual metagenomic shotgun sequencing projects.
=======
A dashboard to visualize shotgun metagenomic sequencing projects.

## Use it

Open `index.html` in a browser, or publish this repository with GitHub Pages. The deployed site automatically loads the committed `dashboard-data/` bundle. The **Choose HPC directory** button remains available for local testing. Local files are never uploaded.

The directory should contain:

```text
project/
├── config.tsv
├── 1-quality-control.sh
├── 2-taxonomic-profiling.sh
├── 3-functional-analysis.sh
└── results/
    ├── taxonomy.csv
    ├── abundance.png
    └── report.html
```

Numbered shell scripts become analysis tabs in numeric order. The first tab displays `config.tsv`. Each script tab shows the script itself, file arguments detected as inputs, output arguments/redirections, and any matching `.html`, `.png`, `.jpg`, `.svg`, `.csv`, or `.tsv` files. Script names are used as tab labels after their numeric prefix is removed.

The directory picker uses the File System Access API where available and falls back to the standard folder upload control. This keeps the app compatible with static hosting such as GitHub Pages.

## Generate a hosted dashboard bundle from the HPC

From the repository checkout on the HPC:

```bash
./scripts/publish_dashboard.sh /hpc/path/to/project "Project 123"
git add dashboard-data
git commit -m "Update dashboard data"
git push
```

The builder copies `config.tsv`, numbered shell scripts, and supported output files referenced by those scripts into `dashboard-data/`, then writes `dashboard-data/manifest.json`. Raw FASTQ/BAM files and other intermediate data are not copied. When the hosted dashboard finds that manifest, it loads the bundle automatically; the local directory picker remains available as a fallback.

The builder reports the number of scripts, inputs, declared outputs, and copied outputs. If a declared output is a shell variable such as `$OUT`, the name is recorded in the manifest but the file cannot be copied automatically; replace it with a concrete path or add the output path explicitly to the script. Supported output arguments include `-o`, `--out`, `--output`, `--output-dir`, `--outdir`, `--outfile`, `--report`, `--html`, shell redirections, and `--output=path` syntax.

## Enable GitHub Pages

The repository includes `.github/workflows/pages.yml`. In the repository settings, open **Pages**, set the source to **GitHub Actions**, and push to `main`. Every subsequent push redeploys the dashboard. After generating a new bundle from the HPC, review the files and run:

```bash
git add dashboard-data
git commit -m "Update dashboard data"
git push origin main
```
