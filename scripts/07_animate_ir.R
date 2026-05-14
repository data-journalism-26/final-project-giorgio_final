suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(terra)
  library(ggplot2)
  library(sf)
  library(rnaturalearth)
  library(tidyterra)
  library(ggtext)
})

# Sibling of 04_animate.R: same map/labels/shipwrecks, IR_108 instead of wind
# + MSLP. Reads the per-frame NetCDFs produced by scripts/06_download_msg.py.
#
# Usage:
#   Rscript 07_animate_ir.R test     # ~9 frames around the storm peak
#   Rscript 07_animate_ir.R full     # every frame in data/msg/ir108/

IR_DIR    <- "data/msg/ir108"
TILES     <- "data/tiles"
OUT       <- "output"
FRAMES    <- file.path(OUT, "frames_ir")
VIDEO_DIR <- file.path(OUT, "video")

dir.create(FRAMES,    showWarnings = FALSE, recursive = TRUE)
dir.create(VIDEO_DIR, showWarnings = FALSE, recursive = TRUE)
sf::sf_use_s2(FALSE)
Sys.setlocale("LC_TIME", "en_US.UTF-8")

# ---- 1. Discover IR frames ----
ir_files <- sort(list.files(IR_DIR, pattern = "^ir108_.*\\.nc$", full.names = TRUE))
if (length(ir_files) == 0)
  stop("No IR_108 NetCDFs in ", IR_DIR, ". Run scripts/06_download_msg.py first.")

# Filename encodes UTC timestamp: ir108_YYYY-MM-DDTHHMM.nc
parse_ts <- function(p) {
  m <- regmatches(p, regexpr("\\d{4}-\\d{2}-\\d{2}T\\d{4}", p))
  as.POSIXct(m, format = "%Y-%m-%dT%H%M", tz = "UTC")
}
ir_times <- as.POSIXct(vapply(ir_files, parse_ts, numeric(1)),
                       origin = "1970-01-01", tz = "UTC")

cat(sprintf("Found %d IR frames | %s -- %s\n",
            length(ir_files),
            format(min(ir_times), "%Y-%m-%d %H:%M"),
            format(max(ir_times), "%Y-%m-%d %H:%M")))

# ---- 2. Static map elements (mirrors 04_animate.R) ----
MAP_X <- c(5, 22)
MAP_Y <- c(29, 42)

# Calabria emphasis: same easing applied in 04_animate.R, kept identical so
# the toggle in the article does not visually flip extent.
ZOOM_START <- as.POSIXct("2026-02-01 00:00", tz = "UTC")
ZOOM_END   <- as.POSIXct("2026-02-07 00:00", tz = "UTC")
ZOOM_X     <- c(13.5, 17.5)
ZOOM_Y     <- c(37.0, 40.0)
extent_for <- function(t) {
  if (t < ZOOM_START)      return(list(x = MAP_X, y = MAP_Y))
  if (t >= ZOOM_END)       return(list(x = ZOOM_X, y = ZOOM_Y))
  p     <- as.numeric(difftime(t, ZOOM_START, units = "secs")) /
           as.numeric(difftime(ZOOM_END, ZOOM_START, units = "secs"))
  p_ease <- 0.5 - 0.5 * cos(pi * p)
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
max_deaths_global <- readRDS(file.path("data/era5/_globals.rds"))$max_deaths_global

# ---- 4. IR colormap ----
# Classic enhanced IR look: warm sea-surface = grey, mid clouds = yellow/orange,
# cold cyclone tops = red/magenta, deep convection = white. Domain matches the
# observed BT range over the storm window (~200-300 K).
ir_breaks  <- c(200, 215, 230, 245, 260, 275, 290, 305)
ir_colours <- c("#FFFFFF", "#E84CB1", "#C12526", "#FFB000",
                "#FFE74C", "#9DC9C9", "#5F6B73", "#1F2A2E")
ir_lim     <- c(200, 305)

base_theme <- theme_minimal(base_size = 11) +
  theme(panel.background = element_rect(fill = NA, colour = NA),
        panel.grid.major = element_line(colour = "grey92", linewidth = 0.2),
        panel.grid.minor = element_blank(),
        plot.title    = element_text(size = 13, face = "bold"),
        plot.subtitle = element_text(size = 9.5, colour = "grey45"),
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
    "<span style='font-size:9.5pt;color:#666666'>Reported shipwrecks: ",
    "<span style='color:#7A1B1B'><b>", n_wrecks, "</b></span></span><br>",
    "<span style='font-size:9.5pt;color:#666666'>Estim. dead or missing: ",
    "<span style='color:#7A1B1B'><b>",
    format(n_deaths, big.mark = ","),
    "</b></span></span>"
  )
}

# ---- 5. Frame builder ----
build_frame <- function(idx, frame_no) {
  t <- ir_times[idx]
  ir <- rast(ir_files[idx], subds = "IR_108")
  ir_df <- as.data.frame(ir, xy = TRUE)
  names(ir_df)[3] <- "bt"

  united_at <- dplyr::filter(united, incident_date_clean <= as.Date(t))
  n_wrecks  <- nrow(united_at)
  n_deaths  <- sum(united_at$n_deaths, na.rm = TRUE)
  ext       <- extent_for(t)
  date_box  <- tibble::tibble(
    x = ext$x[1] + 0.25, y = ext$y[1] + 0.25,
    label = date_label_for(t, n_wrecks, n_deaths))

  p <- ggplot() +
    geom_spatraster_rgb(data = base_tile, alpha = 1, maxcell = 5e5) +
    geom_raster(data = ir_df, aes(x = x, y = y, fill = bt), alpha = 0.85) +
    scale_fill_gradientn(
      colours = ir_colours,
      values  = scales::rescale(ir_breaks, from = ir_lim),
      limits  = ir_lim,
      breaks  = c(210, 240, 270, 300),
      name    = "IR 10.8 µm brightness temperature (K)") +
    geom_sf(data = coast, colour = "grey20", linewidth = 0.18) +
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
               shape = 16, colour = "#D32F2F", size = 3, alpha = 0.95) +
    geom_point(data = dplyr::filter(united_at, n_deaths > 1),
               aes(x = longitude, y = latitude, size = n_deaths),
               shape = 21, fill = "#D32F2F", colour = "#7A1B1B",
               stroke = 0.5, alpha = 0.65) +
    scale_size_continuous(
      range     = c(3, 14),
      transform = "sqrt",
      limits    = c(1, max_deaths_global),
      breaks    = unique(c(1, 10, 100, max_deaths_global)),
      name      = "Number of deaths per shipwreck") +
    guides(
      fill = guide_colourbar(
        title.position = "top",
        barwidth = unit(6, "cm"),
        barheight = unit(0.35, "cm"),
        order = 1),
      size = guide_legend(
        direction = "horizontal",
        title.position = "top",
        label.position = "bottom",
        nrow = 1,
        override.aes = list(fill = "#D32F2F", colour = "#7A1B1B",
                            stroke = 0.5, alpha = 0.65),
        order = 2)) +
    coord_sf(xlim = ext$x, ylim = ext$y, expand = FALSE) +
    labs(title    = "Cyclone Harry over the Central Mediterranean migration route",
         subtitle = "Cloud-top temperature from MSG SEVIRI IR 10.8 µm. Coldest tops (white/magenta) mark the deepest convection.",
         x = NULL, y = NULL) +
    base_theme +
    theme(plot.title    = element_text(size = 16, face = "bold", colour = "grey5"),
          plot.subtitle = element_text(size = 11.5, colour = "grey25", lineheight = 1.15,
                                       margin = margin(t = 2, b = 6)))

  out <- file.path(FRAMES, sprintf("frame_%04d.png", frame_no))
  ggsave(out, p, width = 9, height = 9, dpi = 150)
  invisible(out)
}

# ---- 6. Frame schedule ----
args     <- commandArgs(trailingOnly = TRUE)
mode_arg <- if (length(args) > 0) tolower(args[1]) else "test"

if (mode_arg == "test") {
  # Use whatever's around the storm peak that we have on disk
  target_window <- as.POSIXct(c("2026-01-22 00:00", "2026-01-23 00:00"), tz = "UTC")
  keep_idx <- which(ir_times >= target_window[1] & ir_times <= target_window[2])
  if (length(keep_idx) == 0) {
    cat("No frames in storm-peak window yet -- using all available.\n")
    keep_idx <- seq_along(ir_files)
  }
  framerate <- 4
} else if (mode_arg == "full") {
  keep_idx  <- seq_along(ir_files)
  framerate <- 12
} else {
  stop("Mode must be 'test' or 'full'.")
}

cat(sprintf("Mode: %s | %d frames | framerate %d fps\n",
            mode_arg, length(keep_idx), framerate))

# ---- 7. Render frames ----
unlink(list.files(FRAMES, pattern = "frame_.*\\.png$", full.names = TRUE))
t0 <- Sys.time()
for (i in seq_along(keep_idx)) {
  cat(sprintf("[%d/%d] %s\n", i, length(keep_idx),
              format(ir_times[keep_idx[i]], "%Y-%m-%d %H:%M")))
  build_frame(keep_idx[i], i)
}
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cat(sprintf("Frames rendered in %.1f min (%.1f s/frame)\n",
            elapsed, 60 * elapsed / length(keep_idx)))

# ---- 8. Encode MP4 ----
frame_files <- sort(list.files(FRAMES, pattern = "frame_.*\\.png$", full.names = TRUE))
out_video   <- file.path(VIDEO_DIR, sprintf("cyclone_harry_ir_%s.mp4", mode_arg))
av::av_encode_video(frame_files, output = out_video, framerate = framerate,
                    vfilter = "scale=trunc(iw/2)*2:trunc(ih/2)*2")
cat("Saved:", out_video, "\n")
