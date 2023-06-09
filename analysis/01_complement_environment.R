## ----setup, include=FALSE-------------------------------------------------------------
library(dplyr)
library(ggplot2)
library(tidyr)
library(readr)
library(purrr)
library(rbeni)
library(ingestr)


## -------------------------------------------------------------------------------------
df <- read_csv(paste0(here::here(), "/data-raw/global_leaf_NP_total_Di_20210224.csv")) %>%  #, col_types = "idddcccdddddccccccc") %>%
  rename(lon = lon_estimate,
         lat = lat_estimate,
         elv = Alt_Di_check_final) %>%
  rename(year_start = Sampling_Year_start,
         year_end = Sampling_Year_end) %>%

  ## to be done: make sampling year info machine readable: either in the form of "9999" or "8888_9999"
  separate(Sampling_Month, sep = "_", c("month_start", "month_end")) %>%
  mutate(month_start = as.numeric(month_start), month_end = as.numeric(month_end)) %>%

  ## arrange by year
  arrange(year_start) %>%

  ## create identifier
  mutate(id = paste0("i", seq(nrow(.))))

## save with added ids and site names
write_csv(df, file = paste0(here::here(), "/data-raw/global_leaf_NP_total_Di_20210324_PROC.csv"))

## look at some distributions
df %>%
  ggplot(aes(x = leafN, y = ..density..)) +
  geom_histogram()

df %>%
  ggplot(aes(x = leafP, y = ..density..)) +
  geom_histogram()


## ETOPO (elevation) -------------------------------------------------------------------------------------
# and overwrite file global_leaf_NP_total_Di_20210324_PROC.csv

# df <- read_csv(paste0(here::here(), "/data-raw/global_leaf_NP_total_Di_20210324_PROC.csv"))

df_tmp <- df %>%
  dplyr::filter(is.na(elv)) %>%
  distinct(lon, lat) %>%
  mutate(sitename = paste0("i", seq(nrow(.))))

## extract elevation data from etopo1
df_etopo <- ingest(
  df_tmp,
  source = "etopo1",
  dir = "~/data/etopo/"  # adjust this with your local path
  ) %>%
  unnest(data) %>%

  ## add it again so it has lon and lat
  right_join(df_tmp, by = "sitename") %>%
  ungroup() %>%
  rename(elv_etopo = elv) %>%
  dplyr::select(-sitename)

## add etopo elevation data to data frame
df <- df %>%
  left_join(df_etopo, by = c("lon", "lat")) %>%
  rowwise() %>%
  mutate(elv = ifelse(is.na(elv), elv_etopo, elv)) %>%
  dplyr::select(-elv_etopo) %>%

  ## create new variable site name (sometimes multiple obs are available for one site)
  mutate(sitename = paste0("i_", as.character(lon), "_", as.character(lat), "_", as.character(elv)))

## save with complemented elevation
write_csv(df, file = paste0(here::here(), "/data-raw/global_leaf_NP_total_Di_20210324_PROC.csv"))


## Aggregate to sites --------------------------------------------------------------------
# df <- read_csv("~/data/LeafNP_tiandi/Global_total_leaf_N_P_Di/global_leaf_NP_total_Di_20210324_PROC.csv")

df_sites <- df %>%
  distinct(sitename, lon, lat, elv)

## determine start and end year for each site based on available measurements
df_sites <- df %>% dplyr::select(sitename, year_start, year_end) %>%
  group_by(sitename) %>%
  summarise(year_start = min(year_start, na.rm = TRUE),
            year_end   = max(year_end, na.rm = TRUE)) %>%
  right_join(df_sites, by = "sitename")

write_csv(df_sites, file = paste0(here::here(), "/data-raw/df_sites_leafnp_20210324.csv"))


# ## Check data ---------------------------------------------------------------------------
# tmp <- df %>%
#   group_by(Species) %>%
#   summarise(count = n()) %>%
#   ungroup() %>%
#   arrange(desc(count))
#
# tmp %>%
#   ggplot(aes(x = count, y = ..count..)) +
#   geom_histogram()
#
# ## number of data points with species that have at least 30 observations: 23513
# use_species <- tmp %>%
#   dplyr::filter(count >= 30) %>%
#   pull(Species)
#
# df %>%
#   dplyr::filter(Species %in% use_species) %>%
#   nrow()
#
#
# ## -------------------------------------------------------------------------------------
# tmp <- df %>%
#   group_by(Genus) %>%
#   summarise(count = n()) %>%
#   ungroup() %>%
#   arrange(desc(count))
#
# tmp
#
# tmp %>%
#   ggplot(aes(x = count, y = ..count..)) +
#   geom_histogram()
#
#
# ## -------------------------------------------------------------------------------------
# tmp <- df %>%
#   group_by(Family) %>%
#   summarise(count = n()) %>%
#   ungroup() %>%
#   arrange(desc(count))
#
# tmp
#
# tmp %>%
#   ggplot(aes(x = count, y = ..count..)) +
#   geom_histogram()


## -------------------------------------------------------------------------------------
rbeni::plot_map_simpl() +
  geom_point(data = df_sites, aes(x = lon, y = lat), color = "red", size = 0.3)


## HWSD (soil) -------------------------------------------------------------------------
# df_sites <- read_csv("data/df_sites_leafnp_20210324.csv")

filn <- paste0(here::here(), "/data-raw/df_hwsd_20210324.RData")
if (!file.exists(filn)){

  df_hwsd <- ingest(
    df_sites,
    source = "hwsd",
    settings = list(fil = "~/data/hwsd/HWSD_RASTER/hwsd.bil")
    )

  ## for some it got info for multiple soil types - take only first ones => TEST INFLUENCE OF THIS
  df_hwsd <- df_hwsd %>%
    mutate(n_row = purrr::map_int(data, ~nrow(.))) %>%
    mutate(data = purrr::map(data, ~slice(., 1)))

  df_hwsd <- df_hwsd %>%
    dplyr::select(-n_row) %>%
    unnest(data) %>%
    dplyr::select(sitename, T_BULK_DENSITY, AWC_CLASS, T_CLAY, T_SILT, T_SAND, T_GRAVEL, T_PH_H2O, T_TEB, T_BS, T_CEC_SOIL, T_CEC_CLAY, T_ECE, T_ESP, T_CACO3, T_OC)

  save(df_hwsd, file = filn)

} else {
  load(filn)
}


## WISE (soil) -------------------------------------------------------------------------------------
settings_wise <- get_settings_wise(
  varnam = c("ORGC", "TOTN", "CNrt", "ALSA"),
  layer = 1:2
  )

df_wise <- ingest(
  df_sites,
  source    = "wise",
  settings  = settings_wise,
  dir       = "~/data/soil/wise"
  ) %>%
  unnest(data)  # to get a normal flat table

save(df_wise, file = paste0(here::here(), "/data-raw/df_wise_20210324.RData"))


## GSDE (Soil) -------------------------------------------------------------------------------------
df_sites <- read_csv(paste0(here::here(), "/data-raw/df_sites_leafnp_20210324.csv"))

settings_gsde <- list(varnam =  c("PBR", "PHO", "TP", "TK", "TS"), layer = 1:4)

df_gsde <- ingest(
  df_sites,
  source    = "gsde",
  settings  = settings_gsde,
  dir       = "~/data/soil/shangguan"
  ) %>%
  unnest(data)

save(df_gsde, file = paste0(here::here(), "/data-raw/df_gsde_20210408.RData"))


## CTI -------------------------------------------------------------------------------------
filn <- paste0(here::here(), "/data-raw/df_gti_20210324.RData")
if (!file.exists(filn)){
  rasta <- raster::raster("~/data/gti_marthews/ga2.nc")
  df_gti <- raster::extract(rasta, sp::SpatialPoints(dplyr::select(df_sites, lon, lat) %>% distinct()), sp = TRUE) %>%
    as_tibble() %>%
    rename(gti = GDAL.Band.Number.1) %>%
    right_join(df_sites, by = c("lon", "lat"))
  save(df_gti, file = filn)
} else {
  load(filn)
}


##  CO2 -------------------------------------------------------------------------------------
df_co2 <- ingest(
    df_sites,
    source  = "co2_cmip",
    verbose = FALSE,
    dir = "~/data/co2/"
  ) %>%

  ## aggregate over years per site
  mutate(co2 = purrr::map_dbl(data, ~{summarise(., co2 = mean(co2)) %>% pull(co2)})) %>%
  dplyr::select(-data)

save(df_co2, file = paste0(here::here(), "/data-raw/df_co2_20210324.RData"))


## N-deposition -------------------------------------------------------------------------------------
filn <- paste0(here::here(), "/data-raw/df_ndep_20210324.RData")
if (!file.exists(filn)){
  df_ndep <- ingest(
    df_sites %>%
      mutate(year_start = ifelse(year_start > 2009, 2009, year_start),
             year_end = ifelse(year_end > 2009, 2009, year_end)),
    source    = "ndep",
    timescale = "y",
    dir       = "~/data/ndep_lamarque/",
    getvars   = c("nhx", "noy"),
    verbose   = FALSE
    )
  save(df_ndep, file = filn)
} else {
  load(filn)
}

## take sum of noy and nhx and aggregate over years
df_ndep_agg <- df_ndep %>%
  mutate(data = purrr::map(data, ~mutate(., ndep = noy + nhx))) %>%
  mutate(data = purrr::map(data, ~summarise(., ndep = mean(ndep, na.rm = TRUE)))) %>%
  unnest(data)

save(df_ndep_agg, file = filn)


## P-model outputs --------------------------------------------------------------------
read_pmodel <- function(path){
  load(path)
  return(df_pmodel)
}

df_pmodel <- purrr::map_dfr(as.list(list.files(paste0(here::here(), "/data-raw"),
                                               pattern = "df_pmodel.*.RData",
                                               full.names = TRUE)),
                            ~read_pmodel(.))


## -------------------------------------------------------------------------------------
load(paste0(here::here(), "/data-raw/df_ndep_20210324.RData")) # loads df_ndep_agg
load(paste0(here::here(), "/data-raw/df_co2_20210324.RData")) # df_co2
load(paste0(here::here(), "/data-raw/df_gti_20210324.RData")) # loads df_gti
load(paste0(here::here(), "/data-raw/df_gsde_20210408.RData")) # df_gsde
load( paste0(here::here(), "/data-raw/df_wise_20210324.RData")) # df_wise
load(paste0(here::here(), "/data-raw/df_hwsd_20210324.RData")) # df_hwsd

df <- read_csv(paste0(here::here(), "/data-raw/global_leaf_NP_total_Di_20210324_PROC.csv"))

df_my <- df %>%
  left_join(df_wise, by = "sitename") %>%
  left_join(df_hwsd, by = "sitename") %>%
  left_join(df_gti %>% dplyr::select(-year_start, -year_end, -elv, -lon, -lat), by = "sitename") %>%
  left_join(df_ndep_agg, by = "sitename") %>%
  left_join(df_co2, by = "sitename") %>%
  left_join(df_pmodel, by = "sitename")

## data prepared by di
df_di <- read_csv(paste0(here::here(), "/data-raw/global_leaf_NP_with_soil_property_from_HWSD_WISE_GSDE_23032021.csv"))

## add my extractions to di's soil stuff
df_di <- df_di %>%
  left_join(df_gti %>% dplyr::select(-year_start, -year_end, -elv, -lon, -lat), by = "sitename") %>%
  left_join(df_ndep_agg, by = "sitename") %>%
  left_join(df_co2, by = "sitename") %>%
  left_join(df_pmodel, by = "sitename")

write_csv(df_di, paste0(here::here(), "/data-raw/global_leaf_NP_with_soil_property_from_HWSD_WISE_GSDE_Pmodel_Ndep_GTI_CO2_25032021.csv"))

dim(df_my)
dim(df_di)
dim(df)

names(df_my)

## are my extractions and the one of di the same?
## yes
df_my %>%
  dplyr::select(sitename, T_CACO3_beni = T_CACO3) %>%
  left_join(dplyr::select(df_di, sitename, T_CACO3_di = T_CACO3), by = "sitename") %>%
  rbeni::analyse_modobs2("T_CACO3_beni", "T_CACO3_di", type = "hex")

## yes
df_my %>%
  dplyr::select(sitename, T_PH_H2O_beni = T_PH_H2O) %>%
  left_join(dplyr::select(df_di, sitename, T_PH_H2O_di = T_PH_H2O), by = "sitename") %>%
  rbeni::analyse_modobs2("T_PH_H2O_beni", "T_PH_H2O_di", type = "hex")

df_my %>%
  dplyr::select(sitename, CNrt_beni = CNrt) %>%
  left_join(dplyr::select(df_di, sitename, CNrt_di = CNrt), by = "sitename") %>%
  rbeni::analyse_modobs2("CNrt_beni", "CNrt_di", type = "hex")


## -------------------------------------------------------------------------------------
library(raster)

filn <- "~/data/mct_data/cwdx40.nc"
siteinfo <- tibble(sitename = "id1", lon = 100, lat = 50)  # example for required dataframe structure

## using raster package
rasta <- raster::raster(filn)  # use raster::brick() if data has three dimensions
df <- raster::extract(
    rasta,
    sp::SpatialPoints(dplyr::select(siteinfo, lon, lat)), # , proj4string = sta@crs
    sp = TRUE
    ) %>%
  as_tibble()

## or simply using rbeni
df <- rbeni::extract_pointdata_allsites(filn, df_lonlat = siteinfo)

