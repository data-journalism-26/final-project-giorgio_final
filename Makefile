# Reproducible build for the Cyclone Harry final project.
#
# Default target rebuilds the visual deliverables (static snapshot, ERA5
# animation, IR animation, GeoJSON for the Leaflet map) from cached CSVs and
# NetCDFs.
#
# Heavy steps that touch external resources (`download`, `download-msg`) are
# phony and must be invoked explicitly.

R       := Rscript
PY      := python3

# ---- Inputs (curated CSVs, NetCDFs) ----
# The two incident CSVs are not redistributable; they ship with the repo here
# but the upstream sources require permission. See README.md.
CSV_UNITED := data/united_cyclone_harry.csv
CSV_IOM    := data/iom_cyclone_harry.csv

NC_JAN := data/era5/jan_atm_instant.nc
NC_FEB := data/era5/feb_atm_instant.nc

# ---- Outputs ----
SNAPSHOT  := output/figures/snapshot_2026-01-22_1500Z_mslp.png
VIDEO     := output/video/cyclone_harry_full.mp4
VIDEO_IR  := output/video/cyclone_harry_ir_full.mp4
GEOJSON   := data/incidents_united.geojson

.PHONY: all maps anim anim-ir geojson download download-msg clean help
.DEFAULT_GOAL := all

# ---- Default: rebuild visualisations ----
all: $(SNAPSHOT) $(VIDEO) $(VIDEO_IR) $(GEOJSON)

maps:    $(SNAPSHOT)
anim:    $(VIDEO)
anim-ir: $(VIDEO_IR)
geojson: $(GEOJSON)

# Static snapshot at the storm peak with MSLP contours.
# Also produces the masked basemap tile cache and data/era5/_globals.rds,
# both consumed by the animation scripts (05, 07).
$(SNAPSHOT): scripts/04_era5_basemap.R $(CSV_UNITED) $(NC_JAN)
	$(R) $< peak

# 25-second wind/pressure animation across the whole storm window.
# Depends on the basemap script (04) for the tile cache + globals.
$(VIDEO): scripts/05_era5_animate.R $(SNAPSHOT) $(CSV_UNITED) $(NC_JAN) $(NC_FEB)
	$(R) $< full

# 25-second IR satellite animation across the same window.
# Depends on the basemap script (04) for the tile cache + globals, and on
# the MSG NetCDFs produced by `make download-msg`.
$(VIDEO_IR): scripts/07_msg_animate.R $(SNAPSHOT) $(CSV_UNITED)
	$(R) $< full

# GeoJSON layers consumed by the Leaflet map. Script 02 emits three files;
# we declare one representative output here.
$(GEOJSON): scripts/02_build_geojson.R $(CSV_UNITED) $(CSV_IOM)
	$(R) $<

# ---- Manual / heavy steps (NOT in `all`) ----

# Re-download the ERA5 NetCDFs from Copernicus CDS.
# REQUIRES a free CDS account and a ~/.cdsapirc token, plus minutes-to-hours
# of queue time. Skip unless the .nc files are actually missing.
download:
	$(PY) scripts/03_era5_download.py both

# Re-download the MSG SEVIRI IR NetCDFs from EUMETSAT.
# REQUIRES eumdac, EUMETSAT credentials, and the HRSEVIRI usage licenses.
download-msg:
	$(PY) scripts/06_msg_download.py

# ---- Cleanup ----
clean:
	rm -f $(SNAPSHOT) $(VIDEO) $(VIDEO_IR)
	rm -f data/incidents_united.geojson data/incidents_iom.geojson data/sar_zones.geojson
	rm -rf output/frames

help:
	@echo "Targets:"
	@echo "  make             -> build snapshot, both animations, geojson (default)"
	@echo "  make maps        -> static snapshot only"
	@echo "  make anim        -> wind/pressure animation only"
	@echo "  make anim-ir     -> IR satellite animation only"
	@echo "  make geojson     -> GeoJSON files for the Leaflet map"
	@echo "  make download    -> re-download ERA5 from Copernicus (NEEDS CDS ACCOUNT)"
	@echo "  make download-msg-> re-download MSG IR from EUMETSAT (NEEDS EUMETSAT LICENSE)"
	@echo "  make clean       -> remove generated visualisations"
