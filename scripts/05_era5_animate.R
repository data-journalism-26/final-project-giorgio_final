# ─────────────────────────────────────────────────────────────────────────────
# 05_era5_animate.R — Wind speed + sea-level pressure animation
#
# Purpose:
#   Render the full Cyclone Harry storm window as a 3-hourly animation
#   showing ERA5 wind speed (colour) and MSLP contours, with UNITED
#   shipwreck points and a running death counter overlaid.
#
# Inputs:
#   - data/united_cyclone_harry.csv
#   - data/era5/jan_atm_instant.nc, data/era5/feb_atm_instant.nc
#   - data/era5/_globals.rds                   (from 04_era5_basemap.R)
#   - data/tiles/<provider>_masked.tif         (from 04_era5_basemap.R)
#
# Outputs:
#   - output/frames/frame_NNNN.png             (per-frame PNGs)
#   - output/video/cyclone_harry_full.mp4      (or _test.mp4)
#
# Usage:
#   Rscript scripts/05_era5_animate.R test     # ~9 frames around the storm peak
#   Rscript scripts/05_era5_animate.R full     # ~296 frames, 12 Jan – 17 Feb
#
# Notes:
#   Run scripts/04_era5_basemap.R first. Full render takes ~10 min.
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(terra)
  library(ncdf4)
  library(ggplot2)
  library(sf)
  library(rnaturalearth)
  library(tidyterra)
  library(ggtext)
})

ERA5      <- "data/era5"
TILES     <- "data/tiles"
OUT       <- "output"
FRAMES    <- file.path(OUT, "frames")
VIDEO_DIR <- file.path(OUT, "video")

dir.create(FRAMES,    showWarnings = FALSE, recursive = TRUE)
dir.create(VIDEO_DIR, showWarnings = FALSE, recursive = TRUE)
sf::sf_use_s2(FALSE)
Sys.setlocale("LC_TIME", "en_US.UTF-8")

# ---- 1. ERA5 wind: concatenate Jan + Feb ----
read_times <- function(p) {
  nc <- nc_open(p); on.exit(nc_close(nc))
  as.POSIXct("1970-01-01", tz = "UTC") + ncvar_get(nc, "valid_time")
}

u10 <- c(rast(file.path(ERA5, "jan_atm_instant.nc"), subds = "u10"),
         rast(file.path(ERA5, "feb_atm_instant.nc"), subds = "u10"))
v10 <- c(rast(file.path(ERA5, "jan_atm_instant.nc"), subds = "v10"),
         rast(file.path(ERA5, "feb_atm_instant.nc"), subds = "v10"))
msl <- c(rast(file.path(ERA5, "jan_atm_instant.nc"), subds = "msl"),
         rast(file.path(ERA5, "feb_atm_instant.nc"), subds = "msl"))
times <- c(read_times(file.path(ERA5, "jan_atm_instant.nc")),
           read_times(file.path(ERA5, "feb_atm_instant.nc")))
stopifnot(nlyr(u10) == length(times))

# ---- 2. Static map elements ----
MAP_X <- c(5, 22)
MAP_Y <- c(29, 42)

# Calabria emphasis: from Feb 1 to Feb 7 the camera eases from the wide
# Mediterranean view into a tighter frame around Calabria, where the only
# bodies in the post-cyclone window were recovered (Feb 7+). Aspect ratio of
# the zoomed frame (4 / 3 ~ 1.33) matches the wide one (17 / 13 ~ 1.31), so
# the figure does not letterbox differently between the two states.
ZOOM_START <- as.POSIXct("2026-02-01 00:00", tz = "UTC")
ZOOM_END   <- as.POSIXct("2026-02-07 00:00", tz = "UTC")
ZOOM_X     <- c(13.5, 17.5)
ZOOM_Y     <- c(37.0, 40.0)
extent_for <- function(t) {
  if (t < ZOOM_START)      return(list(x = MAP_X, y = MAP_Y))
  if (t >= ZOOM_END)       return(list(x = ZOOM_X, y = ZOOM_Y))
  p     <- as.numeric(difftime(t, ZOOM_START, units = "secs")) /
           as.numeric(difftime(ZOOM_END, ZOOM_START, units = "secs"))
  p_ease <- 0.5 - 0.5 * cos(pi * p)  # ease in/out
  list(
    x = (1 - p_ease) * MAP_X + p_ease * ZOOM_X,
    y = (1 - p_ease) * MAP_Y + p_ease * ZOOM_Y
  )
}

coast <- ne_coastline(scale = "large", returnclass = "sf")

PROVIDER      <- "CartoDB.VoyagerNoLabels"
basemap_cache <- file.path(TILES, paste0(gsub("[^A-Za-z0-9]+", "-", PROVIDER),
                                         "_z8_masked.tif"))
if (!file.exists(basemap_cache))
  stop("Basemap cache missing. Run scripts/03_snapshot_map.R first to build it.")
base_tile <- rast(basemap_cache)

cities <- tibble::tribble(
  ~name,             ~lon,    ~lat,    ~pos,
  "Tunis",            10.18,   36.81,   "left",
  "Sfax",             10.76,   34.74,   "left",
  "Tripoli",          13.18,   32.89,   "below",
  "Algiers",           3.06,   36.75,   "right",
  "Palermo",          13.36,   38.12,   "below",
  "Catania",          15.09,   37.50,   "right",
  "Cagliari",          9.11,   39.22,   "below",
  "Valletta",         14.51,   35.90,   "below",
  "Lampedusa",        12.60,   35.50,   "right",
  "Reggio Calabria",  15.65,   38.11,   "right",
  "Benghazi",         20.06,   32.12,   "left",
  "Napoli",           14.23,   40.85,   "above"
) |>
  dplyr::mutate(
    nx = dplyr::case_when(pos == "right" ~  0.15, pos == "left" ~ -0.15, TRUE ~ 0),
    ny = dplyr::case_when(pos == "above" ~  0.16, pos == "below" ~ -0.16, TRUE ~ 0),
    hj = dplyr::case_when(pos == "right" ~  0,    pos == "left" ~  1,    TRUE ~ 0.5),
    vj = dplyr::case_when(pos == "above" ~  0,    pos == "below" ~  1,   TRUE ~ 0.5)
  )
seas <- tibble::tribble(
  ~name,                      ~lon,   ~lat,
  "Mediterranean Sea",         16.0,   35.0,
  "Strait of Sicily",          12.6,   36.6,
  "Tyrrhenian Sea",            12.2,   40.0,
  "Ionian Sea",                18.5,   37.5
)

# ---- 3. Shipwrecks ----
.read_smart <- function(p) {
  l1 <- readLines(p, n = 1, warn = FALSE)
  read_delim(p, delim = if (grepl(";", l1)) ";" else ",",
             show_col_types = FALSE)
}
united <- .read_smart("data/united_cyclone_harry.csv")

# ---- 4. Globals (cached) ----
globals <- readRDS(file.path(ERA5, "_globals.rds"))
max_deaths_global <- globals$max_deaths_global
max_wind_lim      <- globals$max_wind_lim

# ---- 5. Style ----
wind_colours <- c("#FFFFFF", "#D2EAF7", "#9EC8E8", "#7DCC4E",
                  "#FFE74C", "#FFA500", "#FF4500", "#9C1F1F")
.wind_ratios <- c(0, 10, 20, 30, 50, 75, 100, 120) / 120
wind_breaks  <- round(.wind_ratios * max_wind_lim, 1)

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.background = element_rect(fill = NA, colour = NA),
        panel.grid.major = element_line(colour = "grey92", linewidth = 0.2),
        panel.grid.minor = element_blank(),
        plot.title    = element_blank(),
        plot.subtitle = element_blank(),
        plot.background = element_rect(fill = "white", colour = NA),
        plot.margin   = margin(0, 0, 4, 0),
        axis.text     = element_blank(),
        axis.ticks    = element_blank(),
        legend.position = "bottom",
        legend.box      = "horizontal",
        legend.justification = "center",
        legend.box.just      = "center",
        legend.box.spacing = unit(8, "pt"),
        legend.spacing.x   = unit(20, "pt"),
        legend.key.size = unit(0.55, "cm"),
        legend.title    = element_text(size = 9),
        legend.text     = element_text(size = 8),
        legend.margin   = margin(t = 4, b = 0))

date_label_for <- function(t, n_wrecks, n_deaths) {
  paste0(
    "<span style='font-size:12pt;color:#1a1a1a'><b>",
    format(t, "%d %B %Y", tz = "Europe/Rome"),
    "</b></span><br>",
    "<span style='font-size:10pt;color:#666666'>",
    format(t, "%H:%M %Z", tz = "Europe/Rome"),
    "</span><br>",
    "<span style='font-size:6pt'>&nbsp;</span><br>",
    "<span style='font-size:9.5pt;color:#666666'>Recorded events: ",
    "<span style='color:#7A1B1B'><b>", n_wrecks, "</b></span></span><br>",
    "<span style='font-size:9.5pt;color:#666666'>Estim. dead or missing: ",
    "<span style='color:#7A1B1B'><b>",
    format(n_deaths, big.mark = ","),
    "</b></span></span>"
  )
}

# ---- 6. Frame builder ----
build_frame <- function(idx, frame_no) {
  ws <- sqrt(u10[[idx]]^2 + v10[[idx]]^2) * 3.6
  ws <- terra::disagg(ws, fact = 4, method = "bilinear")
  names(ws) <- "wind"
  ws_df <- as.data.frame(ws, xy = TRUE)

  msl_at <- msl[[idx]] / 100
  msl_at <- terra::disagg(msl_at, fact = 4, method = "bilinear")
  names(msl_at) <- "msl"
  msl_df <- as.data.frame(msl_at, xy = TRUE)

  t         <- times[idx]
  united_at <- dplyr::filter(united, incident_date_clean <= as.Date(t))
  n_wrecks  <- nrow(united_at)
  n_deaths  <- sum(united_at$n_deaths, na.rm = TRUE)
  ext       <- extent_for(t)
  date_box  <- tibble::tibble(
    x = ext$x[1] + 0.25, y = ext$y[1] + 0.25,
    label = date_label_for(t, n_wrecks, n_deaths))

  p <- ggplot() +
    geom_raster(data = ws_df, aes(x = x, y = y, fill = wind), alpha = 0.88) +
    scale_fill_gradientn(
      colours = wind_colours,
      values  = scales::rescale(wind_breaks),
      limits  = c(0, max_wind_lim),
      breaks  = unique(c(0, 30, 60, max_wind_lim)),
      name    = "Wind speed\n(km/h)") +
    geom_spatraster_rgb(data = base_tile, alpha = 1, maxcell = 5e5) +
    geom_sf(data = coast, colour = "grey20", linewidth = 0.18) +
    geom_contour(data = msl_df,
                 aes(x = x, y = y, z = msl, colour = after_stat(level)),
                 linewidth = 0.5, alpha = 0.9,
                 breaks = seq(980, 1024, by = 4)) +
    scale_colour_distiller(palette = "Blues", direction = -1,
                           name = "Pressure\n(hPa)",
                           limits = c(984, 1024),
                           breaks = c(984, 1004, 1024)) +
    geom_text(data = seas, aes(x = lon, y = lat, label = name),
              size = 4.2, fontface = "italic", colour = "grey25", alpha = 0.85) +
    geom_point(data = cities, aes(x = lon, y = lat),
               size = 0.9, colour = "grey10") +
    geom_text(data = cities,
              aes(x = lon + nx, y = lat + ny, label = name,
                  hjust = hj, vjust = vj),
              size = 3.6, fontface = "bold", colour = "grey10") +
    ggtext::geom_richtext(
      data = date_box,
      aes(x = x, y = y, label = label),
      hjust = 0, vjust = 0,
      family = "sans",
      lineheight = 1.25,
      fill = scales::alpha("white", 0.93),
      label.colour = "grey55",
      label.padding = unit(c(6, 10, 6, 10), "pt"),
      label.r = unit(3, "pt"),
      label.size = 0.4
    ) +
    geom_point(data = dplyr::filter(united_at, n_deaths == 1),
               aes(x = longitude, y = latitude),
               shape = 21, fill = "#1A1A1A", colour = "#000000",
               stroke = 1.0, size = 3, alpha = 0.95) +
    geom_point(data = dplyr::filter(united_at, n_deaths > 1),
               aes(x = longitude, y = latitude, size = n_deaths),
               shape = 21, fill = "#1A1A1A", colour = "#000000",
               stroke = 1.0, alpha = 0.65) +
    scale_size_continuous(
      range     = c(3, 14),
      transform = "sqrt",
      limits    = c(1, max_deaths_global),
      breaks    = unique(c(1, 10, 100, max_deaths_global)),
      name      = "Dead or missing per recorded event") +
    guides(
      fill = guide_colourbar(
        title.position = "top",
        barwidth = unit(5, "cm"),
        barheight = unit(0.35, "cm"),
        order = 1),
      colour = guide_colourbar(
        title.position = "top",
        barwidth = unit(3.5, "cm"),
        barheight = unit(0.35, "cm"),
        reverse = TRUE,
        order = 2),
      size = guide_legend(
        direction = "horizontal",
        title.position = "top",
        label.position = "bottom",
        nrow = 1,
        override.aes = list(fill = "#1A1A1A", colour = "#000000",
                            stroke = 1.0, alpha = 0.65),
        order = 3)) +
    coord_sf(xlim = ext$x, ylim = ext$y, expand = FALSE) +
    labs(x = NULL, y = NULL) +
    base_theme

  out <- file.path(FRAMES, sprintf("frame_%04d.png", frame_no))
  ggsave(out, p, width = 8.5, height = 9, dpi = 150)
  invisible(out)
}

# ---- 7. Frame schedule ----
args     <- commandArgs(trailingOnly = TRUE)
mode_arg <- if (length(args) > 0) tolower(args[1]) else "test"

if (mode_arg == "test") {
  test_seq <- seq(as.POSIXct("2026-01-22 00:00", tz = "UTC"),
                  as.POSIXct("2026-01-23 00:00", tz = "UTC"),
                  by = "3 hour")
  keep_idx <- vapply(test_seq, \(t) which.min(abs(times - t)), integer(1))
  framerate <- 4
} else if (mode_arg == "zoom") {
  # Calabria zoom transition (Feb 1 -> Feb 7) plus a couple of frames on each
  # side, so you can see the wide -> zoomed -> hold sequence.
  test_seq <- seq(as.POSIXct("2026-01-31 18:00", tz = "UTC"),
                  as.POSIXct("2026-02-09 00:00", tz = "UTC"),
                  by = "6 hour")
  keep_idx <- vapply(test_seq, \(t) which.min(abs(times - t)), integer(1))
  framerate <- 4
} else if (mode_arg == "full") {
  start    <- as.POSIXct("2026-01-12 00:00", tz = "UTC")
  end      <- as.POSIXct("2026-02-17 23:00", tz = "UTC")
  step_seq <- seq(start, end, by = "3 hour")
  keep_idx <- vapply(step_seq, \(t) which.min(abs(times - t)), integer(1))
  framerate <- 12
} else {
  stop("Mode must be 'test', 'zoom', or 'full'.")
}

cat(sprintf("Mode: %s | %d frames | framerate %d fps\n",
            mode_arg, length(keep_idx), framerate))

# ---- 8. Render frames ----
unlink(list.files(FRAMES, pattern = "frame_.*\\.png$", full.names = TRUE))
t0 <- Sys.time()
for (i in seq_along(keep_idx)) {
  cat(sprintf("[%d/%d] %s\n", i, length(keep_idx),
              format(times[keep_idx[i]], "%Y-%m-%d %H:%M")))
  build_frame(keep_idx[i], i)
}
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cat(sprintf("Frames rendered in %.1f min (%.1f s/frame)\n",
            elapsed, 60 * elapsed / length(keep_idx)))

# ---- 9. Encode MP4 ----
frame_files <- sort(list.files(FRAMES, pattern = "frame_.*\\.png$", full.names = TRUE))
out_video   <- file.path(VIDEO_DIR, sprintf("cyclone_harry_%s.mp4", mode_arg))
# H.264 requires even pixel dimensions; round down if needed.
av::av_encode_video(frame_files, output = out_video, framerate = framerate,
                    vfilter = "scale=trunc(iw/2)*2:trunc(ih/2)*2")

# Move the MP4 metadata (moov atom) to the front of the file so browsers
# can start playback immediately instead of having to buffer the whole
# file first. Without this, large MP4s stall mid-playback on the web.
qtfaststart <- Sys.which("qtfaststart")
if (nzchar(qtfaststart)) {
  tmp <- paste0(out_video, ".faststart.mp4")
  status <- system2(qtfaststart, c(shQuote(out_video), shQuote(tmp)))
  if (status == 0 && file.exists(tmp)) file.rename(tmp, out_video)
} else {
  warning("qtfaststart not found; the MP4 may stall in browsers. ",
          "Install with: pip3 install qtfaststart")
}
cat("Saved:", out_video, "\n")
