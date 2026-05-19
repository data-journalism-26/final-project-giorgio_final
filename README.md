# The Cyclone Harry on the Central Mediterranean migration route

Giorgio Coppola · GRAD-E1493 Data Journalism, Hertie School · April 2026

A short data journalism piece reconstructing the path of an extratropical cyclone that crossed the Central Mediterranean at the end of January 2026 and overlaying the migrant shipwrecks reported during the same window.

**[Read the piece →](https://data-journalism-26.github.io/final-project-giorgio_final/)**

## Reproduce

```bash
python3 -m http.server 8000    # local preview at http://localhost:8000/
make                            # rebuild animations + GeoJSON (see `make help`)
```

R ≥ 4.3 with `terra`, `ncdf4`, `sf`, `rnaturalearth`, `maptiles`, `tidyterra`, `ggplot2`, `ggtext`, `dplyr`, `readr`, `av`. Python ≥ 3.10 with `cdsapi` only if you re-download ERA5.

## Data

- **ERA5 reanalysis** (wind, MSLP) — Copernicus CDS, not committed (`make download`, CDS account required).
- **MSG SEVIRI IR_108** — EUMETSAT Data Store, not committed (`make download-msg`, HRSEVIRI license required).
- **UNITED *List of Refugee Deaths*** — raw data not redistributed; obtain from <https://unitedagainstrefugeedeaths.eu/> or contact the author for the filtered copy.
- **IOM Missing Migrants Project** — raw data not redistributed; obtain from <https://missingmigrants.iom.int/downloads> or contact the author.
- **IMO Search-and-Rescue zones** — derived GeoJSON ships with the repo.
- **Basemap** — CartoDB Voyager, © OpenStreetMap contributors (ODbL).

## AI disclosure

Claude Code (Anthropic) supported the HTML page design, the Copernicus / EUMETSAT download pipelines, the interactive Leaflet map, the scrollytelling, the reproducibility scripts, and the storm-animation rendering. Editorial decisions, data wrangling, analysis, interpretation, and the writing are the author's.
