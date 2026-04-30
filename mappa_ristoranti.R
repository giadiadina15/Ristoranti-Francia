#!/usr/bin/env Rscript

# Script:
# 1) Scarica CSV ristoranti e GeoJSON dei comuni francesi in locale
# 2) Seleziona il Sud della Francia
# 3) Crea una mappa di densita' dei ristoranti

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(readr)
})

dir.create("data", showWarnings = FALSE, recursive = TRUE)
dir.create("output", showWarnings = FALSE, recursive = TRUE)

csv_url <- "https://raw.githubusercontent.com/holtzy/R-graph-gallery/master/DATA/data_on_french_states.csv"
geojson_url <- "https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/communes.geojson"

csv_path <- file.path("data", "ristoranti_francia.csv")
geojson_path <- file.path("data", "communi_francia.geojson")

download.file(csv_url, destfile = csv_path, mode = "wb")
download.file(geojson_url, destfile = geojson_path, mode = "wb")

message("File scaricati in locale:")
message(" - ", normalizePath(csv_path))
message(" - ", normalizePath(geojson_path))

restaurants <- readr::read_csv(csv_path, show_col_types = FALSE)

# Individua in modo robusto le colonne lon/lat.
possible_lon <- c("long", "lon", "lng", "longitude", "x")
possible_lat <- c("lat", "latitude", "y")

lon_col <- names(restaurants)[tolower(names(restaurants)) %in% possible_lon][1]
lat_col <- names(restaurants)[tolower(names(restaurants)) %in% possible_lat][1]

if (is.na(lon_col) || is.na(lat_col)) {
  stop("Non riesco a trovare colonne longitude/latitude nel CSV.")
}

restaurants <- restaurants %>%
  mutate(
    lon = as.numeric(.data[[lon_col]]),
    lat = as.numeric(.data[[lat_col]])
  ) %>%
  filter(!is.na(lon), !is.na(lat))

restaurants_sf <- st_as_sf(restaurants, coords = c("lon", "lat"), crs = 4326)
communes <- st_read(geojson_path, quiet = TRUE)

# Definizione operativa del Sud della Francia: latitudine <= 45.
south_communes <- communes %>%
  filter(st_coordinates(st_centroid(geometry))[, 2] <= 45)

# Mantiene solo ristoranti nel Sud (spatial join con i comuni selezionati).
restaurants_south <- st_join(restaurants_sf, south_communes, join = st_within, left = FALSE)

if (nrow(restaurants_south) == 0) {
  stop("Nessun ristorante trovato nel Sud con il filtro corrente.")
}

bbox_south <- st_bbox(south_communes)

p <- ggplot() +
  geom_sf(data = south_communes, fill = "grey96", color = "grey80", linewidth = 0.05) +
  stat_density_2d(
    data = cbind(st_drop_geometry(restaurants_south), st_coordinates(restaurants_south)),
    aes(x = X, y = Y, fill = after_stat(level), alpha = after_stat(level)),
    geom = "polygon",
    contour = TRUE,
    n = 300
  ) +
  scale_fill_viridis_c(option = "magma", name = "Densita'") +
  scale_alpha(range = c(0.1, 0.55), guide = "none") +
  coord_sf(
    xlim = c(bbox_south["xmin"], bbox_south["xmax"]),
    ylim = c(bbox_south["ymin"], bbox_south["ymax"]),
    expand = FALSE
  ) +
  labs(
    title = "Mappa di densita' dei ristoranti - Sud della Francia",
    subtitle = "Dati: R Graph Gallery + france-geojson",
    x = NULL,
    y = NULL
  ) +
  theme_minimal(base_size = 12)

output_map <- file.path("output", "mappa_densita_ristoranti_sud_francia.png")
ggsave(output_map, plot = p, width = 10, height = 8, dpi = 300)

message("Mappa salvata in: ", normalizePath(output_map))
