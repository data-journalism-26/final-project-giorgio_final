# The Cyclone Harry on the Central Mediterranean migration route

Giorgio Coppola · GRAD-E1493 Data Journalism, Hertie School · April 2026

A data journalism piece reconstructing the path of an extratropical cyclone that crossed the Central Mediterranean at the end of January 2026 and overlaying the migrant shipwrecks reported during the same window.

**[Read the piece →](https://data-journalism-26.github.io/final-project-giorgio_final/)**

## Reproduce

```bash
python3 -m http.server 8000    # local preview at http://localhost:8000/
make                            # rebuild animations + GeoJSON (see `make help`)
```

R ≥ 4.3 with `terra`, `ncdf4`, `sf`, `rnaturalearth`, `maptiles`, `tidyterra`, `ggplot2`, `ggtext`, `ggforce`, `patchwork`, `cowplot`, `dplyr`, `readr`, `stringr`, `av`. Python ≥ 3.10 with `cdsapi` (for `make download`) and `eumdac`, `satpy`, `pyresample` (for `make download-msg`).

## Data

- **ERA5 reanalysis** (wind, mean sea-level pressure) — Copernicus Climate Data Store (CDS), not committed (`make download`, CDS account required).
- **MSG SEVIRI IR_108** (Meteosat Second Generation Spinning Enhanced Visible and InfraRed Imager, 10.8 µm channel) — EUMETSAT (European Organisation for the Exploitation of Meteorological Satellites) Data Store, not committed (`make download-msg`, HRSEVIRI licence required).
- **UNITED *List of Refugee Deaths*** — raw data not redistributed; obtain from <https://unitedagainstrefugeedeaths.eu/> or contact the author for the filtered copy.
- **IOM (International Organization for Migration) Missing Migrants Project** — raw data not redistributed; obtain from <https://missingmigrants.iom.int/downloads> or contact the author.
- **IMO (International Maritime Organization) Search-and-Rescue zones** — derived GeoJSON ships with the repo.
- **Basemap** — CartoDB Voyager, © OpenStreetMap contributors (Open Database Licence, ODbL).

## AI disclosure

Claude Code (Anthropic) was used as a coding assistant for the HTML page layout, Copernicus/EUMETSAT download pipelines, scrollytelling components, storm-animation rendering, and smaller debugging or implementation tasks. Editorial decisions, data wrangling, analysis, interpretation, and the writing are the author's.
