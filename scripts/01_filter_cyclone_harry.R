suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
})

# UNITED still comes from the upstream thesis RDS (rare external dependency).
# IOM is now read directly from the public Missing Migrants Project CSV
# download placed at data/iom_may_2026.csv. To refresh with a newer MMP
# snapshot, drop the new CSV in `data/` and update IOM_CSV below.
UNITED_RDS <- "/Users/giorgiocoppola/Desktop/Uni/Hertie School/6th Semester/thesis-cmr-mortality/data/processed/united_incidents.RDS"
IOM_CSV    <- "data/iom_may_2026.csv"
OUT_DIR    <- "data"

# ---- UNITED: explicit text filter ----------------------------------------
# UNITED is generated from an external RDS only if it's reachable. When the
# upstream isn't available, leave the existing data/united_cyclone_harry.csv
# untouched and just refresh IOM.
if (file.exists(UNITED_RDS)) {
  united <- readRDS(UNITED_RDS)
  united_harry <- united |>
    filter(str_detect(cause_of_death_text, regex("cyclone Harry", ignore_case = TRUE))) |>
    arrange(incident_date_clean) |>
    mutate(source_dataset = "UNITED")
  stopifnot(nrow(united_harry) > 0)
  united_out <- file.path(OUT_DIR, "united_cyclone_harry.csv")
  write_csv(united_harry, united_out)
  cat("UNITED records:", nrow(united_harry),
      "| total deaths:", sum(united_harry$n_deaths, na.rm = TRUE), "\n")
  cat("Wrote:", united_out, "\n")
} else {
  cat("UNITED RDS not reachable -- keeping existing data/united_cyclone_harry.csv as-is.\n")
}

# ---- IOM: read public MMP CSV, Central Med, Jan 14 - Feb 17 2026 ---------
# The MMP download has its own schema; rename / split into the columns
# the downstream pipeline (05_build_geojson.R, article.html) already expects.
#
# Date strings look like "Fri, 01/23/2026 - 12:00" (US mm/dd/yyyy with the
# weekday prefix). Coordinates are a single "lat, lon" string.
parse_mmp_date <- function(s) {
  m <- regmatches(s, regexpr("[0-9]{2}/[0-9]{2}/[0-9]{4}", s))
  as.Date(m, format = "%m/%d/%Y")
}

stopifnot(file.exists(IOM_CSV))
iom_raw <- read_csv(IOM_CSV, show_col_types = FALSE)

iom_harry <- iom_raw |>
  mutate(
    incident_date_clean = parse_mmp_date(`Incident Date`),
    Latitude  = as.numeric(str_trim(str_split_fixed(Coordinates, ",", 2)[, 1])),
    Longitude = as.numeric(str_trim(str_split_fixed(Coordinates, ",", 2)[, 2])),
    Route     = `Migration route`,
    n_dead    = suppressWarnings(as.integer(`Number Dead`)),
    n_miss    = suppressWarnings(as.integer(`Minimum Estimated Number of Missing`))
  ) |>
  filter(Route == "Central Mediterranean",
         incident_date_clean >= as.Date("2026-01-14"),
         incident_date_clean <= as.Date("2026-02-17")) |>
  arrange(incident_date_clean) |>
  transmute(
    `Main ID`                  = `Main ID`,
    `Incident ID`              = `Incident ID`,
    `Incident Type`            = "Incident",
    `Region of Incident`       = Region,
    `Incident date`            = as.character(incident_date_clean),
    `Incident year`            = Year,
    `Incident month`           = `Reported Month`,
    `No. dead`                 = n_dead,
    `No. missing`              = n_miss,
    `No. dead/missing`         = coalesce(n_dead, 0L) + coalesce(n_miss, 0L),
    `No. survivors`            = suppressWarnings(as.integer(`Number of Survivors`)),
    `No. Female`               = suppressWarnings(as.integer(`Number of Females`)),
    `No. Male`                 = suppressWarnings(as.integer(`Number of Males`)),
    `No. minors`               = suppressWarnings(as.integer(`Number of Children`)),
    `Country of Origin`        = `Country of Origin`,
    `Region of Origin`         = `Region of Origin`,
    `Cause of death (category)` = `Cause of Death`,
    `Cause of death (reported)` = `Cause of Death`,
    Route                      = Route,
    `Country of Incident`      = NA_character_,
    `Location of death`        = `Location of death`,
    `UNSD region`              = `UNSD Geographical Grouping`,
    Source                     = `Information Source`,
    Link                       = URL,
    `Source Quality`           = `Source Quality`,
    Latitude                   = Latitude,
    Longitude                  = Longitude,
    incident_date_clean        = incident_date_clean,
    incident_date_raw          = as.character(incident_date_clean),
    incident_date_precision    = "day",
    source_dataset             = "IOM"
  )

stopifnot(nrow(iom_harry) > 0)

iom_out <- file.path(OUT_DIR, "iom_cyclone_harry.csv")
write_csv(iom_harry, iom_out)
cat("IOM    records:", nrow(iom_harry),
    "| total dead/missing:", sum(iom_harry$`No. dead/missing`, na.rm = TRUE), "\n")
cat("IOM    date range:",
    as.character(min(iom_harry$incident_date_clean)), "to",
    as.character(max(iom_harry$incident_date_clean)), "\n")
cat("IOM    rows missing lat/lon:",
    sum(is.na(iom_harry$Latitude) | is.na(iom_harry$Longitude)), "\n")
cat("Wrote:", iom_out, "\n")
