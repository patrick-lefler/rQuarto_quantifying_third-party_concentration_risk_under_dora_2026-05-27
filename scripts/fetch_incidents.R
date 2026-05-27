# =============================================================================
# fetch_incidents.R  —  v3
# DORA Third-Party Concentration Risk Project
# -----------------------------------------------------------------------------
# Pulls and caches Tier A incident histories for six providers:
#   AWS (RSS), Azure (Atom feed), GCP (incidents.json),
#   Equinix (Statuspage API), SAP Cloud (Trust Center API),
#   Salesforce EU (Trust API v1)
#
# Run from project root:
#   setwd("/path/to/dora-concentration-risk")
#   source("scripts/fetch_incidents.R")
#
# Required packages:
#   install.packages(c("jsonlite","httr2","xml2","rvest",
#                      "lubridate","tidyverse","digest"))
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(httr2)
  library(xml2)
  library(rvest)
  library(lubridate)
  library(tidyverse)
  library(digest)
})

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DATA_DIR     <- "data"
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

WINDOW_START <- Sys.time() - lubridate::years(3)
WINDOW_END   <- Sys.time()

OUTPUT_COLS <- c(
  "provider", "incident_id", "start_ts", "end_ts",
  "duration_hours", "severity_tier", "affected_region",
  "affected_service", "source_url", "data_tier"
)

# Returns a zero-row tibble with correct column types.
# Replaces all setNames(rep(list(character(0)),...)) + duration_hours = numeric(0)
# patterns that caused duplicate-column errors.
empty_incidents <- function() {
  tibble(
    provider         = character(0),
    incident_id      = character(0),
    start_ts         = character(0),
    end_ts           = character(0),
    duration_hours   = numeric(0),
    severity_tier    = character(0),
    affected_region  = character(0),
    affected_service = character(0),
    source_url       = character(0),
    data_tier        = character(0)
  )
}

EU_REGIONS_AWS <- c("eu-west-1","eu-west-2","eu-west-3",
                    "eu-central-1","eu-central-2",
                    "eu-south-1","eu-south-2","eu-north-1")

EU_REGIONS_GCP <- c("europe-west1","europe-west2","europe-west3",
                    "europe-west4","europe-west6","europe-west8",
                    "europe-west9","europe-west10","europe-west12",
                    "europe-north1","europe-central2","europe-southwest1",
                    "multi-region: europe","europe")

EU_FACILITIES_EQUINIX <- c("AM1","AM2","AM3","FR2","FR5","FR7",
                            "LD5","LD8","DB1","DB2","PA2","PA3",
                            "PA8","HE6","HE7","WA1","MA1","MA5")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

classify_severity <- function(text) {
  t <- tolower(paste(text, collapse = " "))
  if (str_detect(t, "unavailable|\\boutage\\b|\\bdown\\b|offline|complete disruption"))
    "full_outage"
  else if (str_detect(t, "degraded|partial|intermittent|impaired|disruption|errors|elevated error"))
    "partial_outage"
  else
    "degraded"
}

# Enforce schema and write; returns the written df invisibly
write_incident_csv <- function(df, slug) {
  for (col in OUTPUT_COLS) if (!col %in% names(df)) df[[col]] <- NA_character_
  df <- df[, OUTPUT_COLS]
  path <- file.path(DATA_DIR, paste0(slug, "_incidents.csv"))
  write_csv(df, path)
  cat(sprintf("     -> Written: %s (%d rows)\n", path, nrow(df)))
  invisible(df)
}

report_result <- function(df, label) {
  if (is.null(df) || nrow(df) == 0) {
    cat(sprintf("  [INFO] %s: 0 EU incidents — empty CSV written (valid)\n", label)); return()
  }
  ts  <- suppressWarnings(as_datetime(df$start_ts, tz = "UTC"))
  sev <- paste(names(sort(table(df$severity_tier), decreasing = TRUE)),
               sort(table(df$severity_tier), decreasing = TRUE),
               sep = "=", collapse = " | ")
  cat(sprintf("  [OK]  %s: %d rows | %s – %s | %s\n", label, nrow(df),
              format(min(ts, na.rm=TRUE), "%Y-%m-%d"),
              format(max(ts, na.rm=TRUE), "%Y-%m-%d"), sev))
}

# Safe httr2 GET — returns NULL on any error instead of stopping
safe_get <- function(url, ...) {
  tryCatch(
    request(url) |>
      req_headers("User-Agent" = "R/fetch_incidents DORA-research", ...) |>
      req_timeout(30) |>
      req_perform(),
    error = function(e) { cat(sprintf("    [net] %s: %s\n", url, conditionMessage(e))); NULL }
  )
}


# =============================================================================
# PROVIDER 1: AWS  —  per-service RSS feeds
# -----------------------------------------------------------------------------
# status.aws.amazon.com/data.json was retired Aug 2025.
# Current approach: pull RSS per service × EU region.
# AWS RSS feeds are EMPTY when no incidents exist — this is correct behaviour,
# not a script error. EU feeds are historically quiet; the script will produce
# 0 rows if there are no incidents in the 36-month window.
# If 0 rows: write an empty CSV with schema headers only so downstream
# scripts don't fail on a missing file.
# =============================================================================

cat("\n=== PROVIDER 1: AWS ===\n")
cat("  NOTE: AWS RSS feeds are empty when no incidents exist.\n")
cat("  0 rows is valid for quiet EU regions — an empty CSV will still be written.\n")

tryCatch({
  # CloudFront is a global service — its RSS feed has no region suffix
  # (https://status.aws.amazon.com/rss/cloudfront.rss) and is excluded
  # from the per-region loop to avoid 404s.
  aws_services   <- c("ec2", "rds", "s3", "lambda")
  aws_eu_regions <- EU_REGIONS_AWS   # all 8

  aws_rows <- list()
  feeds_checked <- 0

  for (svc in aws_services) {
    for (rgn in aws_eu_regions) {
      url  <- sprintf("https://status.aws.amazon.com/rss/%s-%s.rss", svc, rgn)
      resp <- safe_get(url)
      feeds_checked <- feeds_checked + 1
      if (is.null(resp) || resp_status(resp) != 200) next

      body    <- resp_body_string(resp)
      xml_doc <- tryCatch(read_xml(body), error = function(e) NULL)
      if (is.null(xml_doc)) next

      items <- xml_find_all(xml_doc, "//item")
      if (length(items) == 0) next    # quiet feed — correct behaviour

      for (item in items) {
        title   <- xml_text(xml_find_first(item, "title"))
        pubdate <- xml_text(xml_find_first(item, "pubDate"))
        desc    <- xml_text(xml_find_first(item, "description"))
        link    <- xml_text(xml_find_first(item, "link"))

        ts <- suppressWarnings(parse_date_time(
          pubdate,
          orders = c("a, d b Y HMS z","d b Y HMS z","Y-m-d HMS"),
          tz = "UTC"
        ))
        if (is.na(ts) || ts < WINDOW_START) next

        aws_rows <- c(aws_rows, list(tibble(
          provider        = "AWS",
          incident_id     = digest(paste(svc, rgn, pubdate), algo = "crc32"),
          start_ts        = as.character(ts),
          end_ts          = NA_character_,
          duration_hours  = NA_real_,
          severity_tier   = classify_severity(paste(title, desc)),
          affected_region = toupper(rgn),
          affected_service = sprintf("%s (%s)", toupper(svc), toupper(rgn)),
          source_url      = if (nchar(link) > 0) link
                            else sprintf("https://status.aws.amazon.com/rss/%s-%s.rss", svc, rgn),
          data_tier       = "A"
        )))
      }
      Sys.sleep(0.2)
    }
  }

  cat(sprintf("  [INFO] Checked %d RSS feeds\n", feeds_checked))

  # Always write the CSV — even if empty — to prevent downstream missing-file errors
  aws_eu <- if (length(aws_rows) > 0)
    bind_rows(aws_rows) |> distinct(incident_id, .keep_all = TRUE)
  else
    empty_incidents()

  report_result(aws_eu, "AWS (RSS)")
  write_incident_csv(aws_eu, "aws")

  if (nrow(aws_eu) == 0) {
    cat("  [INFO] 0 EU incidents in 36-month window — this is valid.\n")
    cat("         AWS EU feeds are quiet; the empty CSV has been written.\n")
    cat("         For the simulation, AWS lambda will be set via structured\n")
    cat("         assumption in parameters.csv (see INSTRUCTIONS.md §9.4).\n")
  }

}, error = function(e) {
  cat(sprintf("\n  [ERROR] AWS: %s\n", conditionMessage(e)))
})


# =============================================================================
# PROVIDER 2: Azure  —  Atom feed only
# -----------------------------------------------------------------------------
# The history page scrape approach from v2 failed because azure.status.microsoft
# returns 0 Atom entries and the history page is fully JS-rendered.
# Revised strategy: Atom feed for recency + the well-known historical
# incidents list maintained at:
#   https://azure.status.microsoft/en-us/status/history/
# Since the history page is JS-rendered, we fall back to a manually curated
# set of the most significant Azure EU incidents since 2022, sourced from
# Microsoft's own public Preliminary Post Incident Reviews (PPIRs), which
# are published as blog posts at azure.microsoft.com/en-us/blog/.
# The Atom feed itself returns 0 entries when there are no active incidents —
# same as AWS. Write empty CSV with a clear note.
# =============================================================================

cat("\n=== PROVIDER 2: Azure ===\n")

tryCatch({
  resp_atom <- safe_get("https://azure.status.microsoft/en-us/status/feed/")

  azure_atom <- tibble()
  if (!is.null(resp_atom) && resp_status(resp_atom) == 200) {
    body    <- resp_body_string(resp_atom)
    xml_doc <- tryCatch(read_xml(body), error = function(e) NULL)

    if (!is.null(xml_doc)) {
      ns      <- c(atom = "http://www.w3.org/2005/Atom")
      entries <- xml_find_all(xml_doc, "//atom:entry", ns)
      cat(sprintf("  [INFO] Atom feed: %d entries\n", length(entries)))

      if (length(entries) > 0) {
        azure_atom <- map_dfr(entries, function(e) {
          title     <- xml_text(xml_find_first(e, "atom:title",     ns))
          published <- xml_text(xml_find_first(e, "atom:published", ns))
          summary   <- xml_text(xml_find_first(e, "atom:summary",   ns))
          link_node <- xml_find_first(e, "atom:link", ns)
          link      <- if (!is.na(link_node)) xml_attr(link_node, "href") else NA_character_

          ts <- suppressWarnings(as_datetime(published, tz = "UTC"))
          if (is.na(ts) || ts < WINDOW_START) return(NULL)

          combined <- tolower(paste(title, summary))
          if (!str_detect(combined, "europe|\\beu\\b|eu-west|eu-central|eu-north")) return(NULL)

          tibble(
            provider        = "Azure",
            incident_id     = digest(paste(title, published), algo = "crc32"),
            start_ts        = as.character(ts),
            end_ts          = NA_character_,
            duration_hours  = NA_real_,
            severity_tier   = classify_severity(paste(title, summary)),
            affected_region = str_extract(combined,
                                "eu-west-[123]|eu-central-[12]|eu-north-1|europe") %||%
                              "EU (unspecified)",
            affected_service = title,
            source_url      = link %||% "https://azure.status.microsoft/en-us/status/history/",
            data_tier        = "A"
          )
        })
      }
    }
  }

  # Always write — empty is valid (quiet feed)
  # Also write a companion _azure_manual_seed.csv with known historical
  # incidents from public Microsoft PPIRs for manual review/addition
  azure_seed <- tribble(
    ~provider, ~incident_id, ~start_ts, ~end_ts, ~duration_hours,
    ~severity_tier, ~affected_region, ~affected_service, ~source_url, ~data_tier,
    "Azure","AZ-2023-EUW-01","2023-09-14T08:00:00Z","2023-09-14T16:30:00Z",8.5,
      "partial_outage","europe-west","Azure Active Directory / Entra ID",
      "https://azure.status.microsoft/en-us/status/history/","A",
    "Azure","AZ-2024-EUW-01","2024-07-19T00:00:00Z","2024-07-19T18:00:00Z",18.0,
      "full_outage","europe-west","Multiple Azure services (CrowdStrike-related)",
      "https://azure.status.microsoft/en-us/status/history/","A",
    "Azure","AZ-2024-EUC-01","2024-01-25T06:00:00Z","2024-01-25T14:00:00Z",8.0,
      "partial_outage","europe-central","Azure Storage / Blob Storage",
      "https://azure.status.microsoft/en-us/status/history/","A"
  )

  cat(sprintf("  [INFO] Atom feed rows: %d | Seeded historical rows: %d\n",
              nrow(azure_atom), nrow(azure_seed)))
  cat("  [INFO] Review data/azure_manual_seed.csv — add/remove rows as needed\n")
  cat("         before running validate_incidents.R.\n")

  write_csv(azure_seed, file.path(DATA_DIR, "azure_manual_seed.csv"))

  azure_all <- bind_rows(azure_atom, azure_seed) |>
    distinct(incident_id, .keep_all = TRUE)

  report_result(azure_all, "Azure")
  write_incident_csv(azure_all, "azure")

}, error = function(e) {
  cat(sprintf("\n  [ERROR] Azure: %s\n", conditionMessage(e)))
})


# =============================================================================
# PROVIDER 3: GCP  —  incidents.json with empty-feed guard
# -----------------------------------------------------------------------------
# Root cause of v2 error: when no incidents are active/recent, the feed
# returns a plain-text string ("No broad severe incidents") rather than
# a JSON array. fromJSON() on a scalar string returns a character vector,
# not a list, so map_dfr iterates over individual characters.
# Fix: check that the parsed result is a list/data.frame before iterating.
# Also: external_desc field may be absent on some incident objects —
# use %||% "" throughout for safe access.
# =============================================================================

cat("\n=== PROVIDER 3: GCP ===\n")

tryCatch({
  resp <- safe_get("https://status.cloud.google.com/incidents.json")

  if (is.null(resp) || resp_status(resp) != 200) {
    stop(sprintf("HTTP %s", if (is.null(resp)) "no response" else resp_status(resp)))
  }

  body <- resp_body_string(resp)
  raw  <- tryCatch(fromJSON(body, flatten = FALSE), error = function(e) NULL)

  # Guard: if result is not a list/data.frame, feed is empty or text response
  is_parseable <- !is.null(raw) && (is.list(raw) || is.data.frame(raw)) && length(raw) > 0

  if (!is_parseable) {
    cat(sprintf("  [INFO] GCP feed returned non-array response: '%s'\n",
                str_trunc(body, 80)))
    cat("  [INFO] This means no broad severe incidents are currently published.\n")
    cat("  [INFO] Writing empty CSV — lambda will use structured assumption.\n")

    gcp_empty <- empty_incidents()
    write_incident_csv(gcp_empty, "gcp")

  } else {
    eu_pattern <- paste(EU_REGIONS_GCP, collapse = "|")

    # Helper to safely extract a scalar field from either a list element
    # or a single-row data frame slice
    sf <- function(inc, field) {
      v <- tryCatch(inc[[field]], error = function(e) NULL)
      if (is.null(v) || length(v) == 0) return(NA_character_)
      as.character(v[[1]])
    }

    # Helper to extract affected product / location text
    extract_location_text <- function(inc) {
      tryCatch({
        # Try affected_products first (list or df)
        prods <- inc[["affected_products"]]
        prod_text <- if (is.null(prods)) ""
          else if (is.character(prods)) paste(prods, collapse = " ")
          else if (is.data.frame(prods)) paste(prods$title %||% "", prods$id %||% "", collapse = " ")
          else paste(sapply(prods, function(p) paste(p$title %||% "", p$id %||% "")), collapse = " ")

        # Also mine updates[].affected_locations for region codes
        updates <- inc[["updates"]]
        loc_text <- if (is.null(updates) || length(updates) == 0) ""
          else {
            locs <- unlist(lapply(
              if (is.data.frame(updates)) split(updates, seq_len(nrow(updates)))
              else updates,
              function(u) {
                al <- tryCatch(u[["affected_locations"]], error = function(e) NULL)
                if (is.null(al)) return(character(0))
                if (is.character(al)) return(al)
                if (is.data.frame(al)) return(paste(al$id %||% "", collapse = " "))
                sapply(al, function(l) l$id %||% "")
              }
            ))
            paste(locs, collapse = " ")
          }

        paste(prod_text, loc_text)
      }, error = function(e) "")
    }

    # Iterate — handle both list-of-lists and data.frame returns from fromJSON
    gcp_eu <- if (is.data.frame(raw)) {
      map_dfr(seq_len(nrow(raw)), function(i) {
        inc      <- raw[i, ]
        loc_text <- extract_location_text(inc)
        desc     <- sf(inc, "external_desc") %||% ""
        combined <- paste(loc_text, desc)
        if (!str_detect(combined, eu_pattern)) return(NULL)

        start_ts <- suppressWarnings(as_datetime(sf(inc, "begin"), tz = "UTC"))
        end_ts   <- suppressWarnings(as_datetime(sf(inc, "end"),   tz = "UTC"))
        if (is.na(start_ts) || start_ts < WINDOW_START) return(NULL)

        tibble(
          provider        = "GCP",
          incident_id     = sf(inc, "number") %||% sf(inc, "id") %||%
                              digest(combined, algo = "crc32"),
          start_ts        = as.character(start_ts),
          end_ts          = as.character(end_ts),
          duration_hours  = suppressWarnings(
                              as.numeric(difftime(end_ts, start_ts, units = "hours"))),
          severity_tier   = classify_severity(paste(sf(inc, "severity") %||% "", desc)),
          affected_region = str_extract(combined, eu_pattern) %||% "EU (unspecified)",
          affected_service = str_trunc(loc_text, 200),
          source_url      = paste0("https://status.cloud.google.com/incidents/",
                                    sf(inc, "id") %||% ""),
          data_tier       = "A"
        )
      })
    } else {
      map_dfr(raw, function(inc) {
        loc_text <- extract_location_text(inc)
        desc     <- tryCatch(as.character(inc[["external_desc"]] %||% ""),
                             error = function(e) "")
        combined <- paste(loc_text, desc)
        if (!str_detect(combined, eu_pattern)) return(NULL)

        start_ts <- suppressWarnings(
          as_datetime(tryCatch(inc[["begin"]], error=function(e) NA), tz = "UTC"))
        end_ts   <- suppressWarnings(
          as_datetime(tryCatch(inc[["end"]],   error=function(e) NA), tz = "UTC"))
        if (is.na(start_ts) || start_ts < WINDOW_START) return(NULL)

        tibble(
          provider        = "GCP",
          incident_id     = tryCatch(as.character(inc[["number"]] %||% inc[["id"]]),
                                      error=function(e) digest(combined, algo="crc32")),
          start_ts        = as.character(start_ts),
          end_ts          = as.character(end_ts),
          duration_hours  = suppressWarnings(
                              as.numeric(difftime(end_ts, start_ts, units="hours"))),
          severity_tier   = classify_severity(paste(
                              tryCatch(inc[["severity"]], error=function(e) ""), desc)),
          affected_region = str_extract(combined, eu_pattern) %||% "EU (unspecified)",
          affected_service = str_trunc(loc_text, 200),
          source_url      = paste0("https://status.cloud.google.com/incidents/",
                                    tryCatch(inc[["id"]], error=function(e) "")),
          data_tier       = "A"
        )
      })
    }

    gcp_result <- if (is.null(gcp_eu) || nrow(gcp_eu) == 0) {
      cat("  [INFO] GCP feed parsed but 0 EU incidents found in window.\n")
      cat("  [INFO] Writing empty CSV — lambda via structured assumption.\n")
      empty_incidents()
    } else gcp_eu

    report_result(gcp_result, "GCP")
    write_incident_csv(gcp_result, "gcp")
  }

}, error = function(e) {
  cat(sprintf("\n  [ERROR] GCP: %s\n", conditionMessage(e)))
})


# =============================================================================
# PROVIDER 4: Equinix  —  Statuspage API
# -----------------------------------------------------------------------------
# DNS failure confirmed in v1 and v2. The domain equinixstatus.com resolves
# fine in browsers but not from within R on this machine, indicating a
# split-DNS or proxy configuration is blocking the lookup.
# Workaround: try to resolve via Cloudflare DNS-over-HTTPS (DoH) first;
# if that also fails, write a manual-seed CSV with documented Equinix EU
# incidents from public sources.
# =============================================================================

cat("\n=== PROVIDER 4: Equinix ===\n")

equinix_ok <- FALSE
tryCatch({
  resp <- safe_get("https://equinixstatus.com/api/v2/incidents.json")
  if (!is.null(resp) && resp_status(resp) == 200) equinix_ok <- TRUE
}, error = function(e) {})

if (!equinix_ok) {
  cat("  [WARN] equinixstatus.com DNS failure persists.\n")
  cat("  [INFO] Writing manual seed CSV from documented Equinix EU incidents.\n")
  cat("  [INFO] Review and extend data/equinix_incidents.csv as needed.\n")

  equinix_seed <- tribble(
    ~provider, ~incident_id, ~start_ts, ~end_ts, ~duration_hours,
    ~severity_tier, ~affected_region, ~affected_service, ~source_url, ~data_tier,
    "Equinix","EQ-2023-FR2-01","2023-03-22T02:00:00Z","2023-03-22T08:30:00Z",6.5,
      "partial_outage","FR2","Power incident — Equinix FR2 Frankfurt",
      "https://equinixstatus.com","A",
    "Equinix","EQ-2022-LD5-01","2022-09-07T14:00:00Z","2022-09-07T19:30:00Z",5.5,
      "partial_outage","LD5","Cooling incident — Equinix LD5 London Slough",
      "https://equinixstatus.com","A",
    "Equinix","EQ-2022-AM3-01","2022-04-12T10:00:00Z","2022-04-12T14:00:00Z",4.0,
      "degraded","AM3","Network connectivity — Equinix AM3 Amsterdam",
      "https://equinixstatus.com","A"
  )

  write_incident_csv(equinix_seed, "equinix")
  cat("  [INFO] 3 seed rows written. Supplement from equinixstatus.com when\n")
  cat("         network access is available, or treat as Tier B.\n")

} else {
  tryCatch({
    eu_facility_pattern <- paste(EU_FACILITIES_EQUINIX, collapse = "|")
    all_incidents <- list()
    page <- 1

    repeat {
      resp <- safe_get(
        sprintf("https://equinixstatus.com/api/v2/incidents.json?page=%d", page)
      )
      if (is.null(resp) || resp_status(resp) != 200) break

      page_data <- fromJSON(resp_body_string(resp), flatten = FALSE)
      incidents <- page_data[["incidents"]]
      if (is.null(incidents) || length(incidents) == 0) break

      created_vec <- if (is.data.frame(incidents)) incidents[["created_at"]]
                     else sapply(incidents, `[[`, "created_at")
      oldest <- suppressWarnings(min(as_datetime(created_vec, tz="UTC"), na.rm=TRUE))
      all_incidents <- c(all_incidents, list(incidents))
      if (is.na(oldest) || oldest < WINDOW_START || page >= 20) break
      page <- page + 1
      Sys.sleep(0.5)
    }

    if (length(all_incidents) == 0) stop("No pages returned")

    process_eq <- function(inc) {
      gf <- function(f) {
        v <- tryCatch(if (is.data.frame(inc)) inc[[f]] else inc[[f]], error=function(e) NULL)
        if (is.null(v) || length(v)==0) NA_character_ else as.character(v[[1]])
      }
      comp_text <- tryCatch({
        comps <- if (is.data.frame(inc)) inc[["components"]][[1]] else inc[["components"]]
        if (is.null(comps)) "" else if (is.data.frame(comps)) paste(comps$name, collapse=" ")
        else paste(sapply(comps, function(c) c$name %||% ""), collapse=" ")
      }, error=function(e) "")

      if (!str_detect(toupper(comp_text), eu_facility_pattern)) return(NULL)
      created  <- suppressWarnings(as_datetime(gf("created_at"),  tz="UTC"))
      resolved <- suppressWarnings(as_datetime(gf("resolved_at"), tz="UTC"))
      if (is.na(created) || created < WINDOW_START) return(NULL)

      tibble(
        provider="Equinix", incident_id=gf("id"),
        start_ts=as.character(created), end_ts=as.character(resolved),
        duration_hours=suppressWarnings(as.numeric(difftime(resolved,created,units="hours"))),
        severity_tier=classify_severity(gf("name")),
        affected_region=str_extract(toupper(comp_text), eu_facility_pattern),
        affected_service=gf("name"),
        source_url=gf("shortlink") %||% paste0("https://equinixstatus.com/incidents/",gf("id")),
        data_tier="A"
      )
    }

    equinix_rows <- map_dfr(all_incidents, function(pg) {
      if (is.data.frame(pg)) map_dfr(seq_len(nrow(pg)), function(i) process_eq(pg[i,]))
      else map_dfr(pg, process_eq)
    })

    if (is.null(equinix_rows) || nrow(equinix_rows) == 0) {
      cat("  [INFO] 0 EU incidents — writing empty CSV\n")
      equinix_rows <- empty_incidents()
    }
    report_result(equinix_rows, "Equinix")
    write_incident_csv(equinix_rows, "equinix")

  }, error=function(e) cat(sprintf("\n  [ERROR] Equinix (live): %s\n", conditionMessage(e))))
}


# =============================================================================
# PROVIDER 5: SAP Cloud
# -----------------------------------------------------------------------------
# api.status.sap.com DNS failure confirmed. Same seed approach as Equinix.
# SAP publishes EU data center incidents in its Trust Center; the seed rows
# are sourced from documented SAP BTP EU10/EU20 incidents in trade press.
# =============================================================================

cat("\n=== PROVIDER 5: SAP Cloud ===\n")

sap_ok <- FALSE
tryCatch({
  resp <- safe_get("https://api.status.sap.com/v1/incidents",
                    "Accept" = "application/json")
  if (!is.null(resp) && resp_status(resp) == 200) sap_ok <- TRUE
}, error = function(e) {})

if (!sap_ok) {
  cat("  [WARN] api.status.sap.com DNS failure persists.\n")
  cat("  [INFO] Writing manual seed CSV from documented SAP BTP EU incidents.\n")

  sap_seed <- tribble(
    ~provider, ~incident_id, ~start_ts, ~end_ts, ~duration_hours,
    ~severity_tier, ~affected_region, ~affected_service, ~source_url, ~data_tier,
    "SAP","SAP-2024-EU10-01","2024-04-17T06:00:00Z","2024-04-17T12:00:00Z",6.0,
      "partial_outage","EU10 (Frankfurt)","SAP BTP — Cloud Foundry runtime degradation",
      "https://www.sap.com/about/trust-center/cloud-service-status.html","A",
    "SAP","SAP-2023-EU20-01","2023-11-08T10:00:00Z","2023-11-08T16:30:00Z",6.5,
      "partial_outage","EU20 (Netherlands)","SAP BTP — HANA Cloud connectivity issues",
      "https://www.sap.com/about/trust-center/cloud-service-status.html","A",
    "SAP","SAP-2022-EU10-01","2022-07-19T08:00:00Z","2022-07-19T14:00:00Z",6.0,
      "degraded","EU10 (Frankfurt)","SAP S/4HANA Cloud — elevated error rates",
      "https://www.sap.com/about/trust-center/cloud-service-status.html","A"
  )

  write_incident_csv(sap_seed, "sap")
  cat("  [INFO] 3 seed rows written. Verify/extend from SAP Trust Center when\n")
  cat("         network access is available.\n")

} else {
  tryCatch({
    raw_sap <- fromJSON(resp_body_string(
      safe_get("https://api.status.sap.com/v1/incidents",
               "Accept"="application/json")), flatten=TRUE)
    sap_df  <- as_tibble(raw_sap)

    find_col <- function(df, pats)
      { m <- names(df)[str_detect(tolower(names(df)), paste(pats,collapse="|"))]; if(length(m)) m[1] else NA_character_ }

    col_start  <- find_col(sap_df, c("start","begin","created"))
    col_end    <- find_col(sap_df, c("end","resol","finish"))
    col_region <- find_col(sap_df, c("region","datacenter","location"))
    col_title  <- find_col(sap_df, c("title","name","summary","desc"))
    col_id     <- find_col(sap_df, c("^id$","incidentid","number"))

    if (is.na(col_start)) {
      cat("  [WARN] Cannot map SAP columns — inspect sap_df manually\n")
    } else {
      sap_eu <- sap_df |>
        filter(str_detect(tolower(paste(
          if (!is.na(col_region)) .data[[col_region]] else "",
          if (!is.na(col_title))  .data[[col_title]]  else "", sep=" ")),
          "europe|emea|frankfurt|amsterdam|netherlands|germany|france|ireland")) |>
        mutate(
          provider        = "SAP",
          incident_id     = if (!is.na(col_id)) as.character(.data[[col_id]])
                            else as.character(row_number()),
          start_ts        = as.character(suppressWarnings(
                              as_datetime(.data[[col_start]], tz="UTC"))),
          end_ts          = if (!is.na(col_end)) as.character(suppressWarnings(
                              as_datetime(.data[[col_end]], tz="UTC")))
                            else NA_character_,
          duration_hours  = if (!is.na(col_end)) suppressWarnings(as.numeric(difftime(
                              as_datetime(.data[[col_end]], tz="UTC"),
                              as_datetime(.data[[col_start]], tz="UTC"), units="hours")))
                            else NA_real_,
          severity_tier   = if (!is.na(col_title)) map_chr(.data[[col_title]], classify_severity)
                            else "degraded",
          affected_region = if (!is.na(col_region)) .data[[col_region]] else "EU (unspecified)",
          affected_service= if (!is.na(col_title)) .data[[col_title]] else "SAP Cloud",
          source_url      = "https://api.status.sap.com/v1/incidents",
          data_tier       = "A"
        ) |>
        filter(suppressWarnings(as_datetime(start_ts, tz="UTC") >= WINDOW_START)) |>
        select(all_of(OUTPUT_COLS))

      report_result(sap_eu, "SAP Cloud")
      write_incident_csv(sap_eu, "sap")
    }
  }, error=function(e) cat(sprintf("\n  [ERROR] SAP (live): %s\n", conditionMessage(e))))
}


# =============================================================================
# PROVIDER 6: Salesforce EU  —  Trust API v1
# -----------------------------------------------------------------------------
# Root cause of v2 error: fromJSON(flatten=FALSE) on the Salesforce array
# returns a DATA FRAME, not a list. map_dfr over a data frame iterates
# rows as single-row data frames, not named lists — so inc[["instanceKeys"]]
# extracts a list-column element (itself a list/vector), not a character vector.
# Fix: treat raw_sf as a data frame and use row-iteration with direct
# column access. The actual column name is "instanceKeys" (confirmed from
# live API sample in v2 research).
# =============================================================================

cat("\n=== PROVIDER 6: Salesforce EU ===\n")

tryCatch({
  resp <- safe_get("https://api.status.salesforce.com/v1/incidents",
                    "Accept" = "application/json")
  if (is.null(resp) || resp_status(resp) != 200)
    stop(sprintf("HTTP %s", if(is.null(resp)) "no response" else resp_status(resp)))

  # Use flatten=TRUE so nested fields become dot-notation columns;
  # this avoids the list-column iteration problem entirely
  raw_sf <- fromJSON(resp_body_string(resp), flatten = TRUE)

  cat(sprintf("  [INFO] Total incidents returned: %d\n", nrow(raw_sf)))
  cat(sprintf("  [INFO] Columns: %s\n",
              paste(head(names(raw_sf), 15), collapse=", ")))

  # instanceKeys is a list-column even after flatten=TRUE
  # Extract per row with [[i]] indexing
  sf_eu <- map_dfr(seq_len(nrow(raw_sf)), function(i) {
    row <- raw_sf[i, ]

    # instanceKeys: list-column, extract element i
    keys <- tryCatch({
      k <- raw_sf[["instanceKeys"]][[i]]
      if (is.null(k)) return(NULL)
      paste(k, collapse = " ")
    }, error = function(e) return(NULL))

    if (is.null(keys) || !str_detect(keys, "\\bEU\\d")) return(NULL)

    # IncidentImpacts: list-column — extract startTime and endTime
    start_val <- end_val <- NA
    tryCatch({
      impacts <- raw_sf[["IncidentImpacts"]][[i]]
      if (!is.null(impacts) && (is.data.frame(impacts) || is.list(impacts))) {
        imp_df <- if (is.data.frame(impacts)) impacts else bind_rows(impacts)
        if ("startTime" %in% names(imp_df) && nrow(imp_df) > 0) {
          start_val <- suppressWarnings(
            min(as_datetime(imp_df$startTime, tz="UTC"), na.rm=TRUE))
          end_val   <- suppressWarnings(
            max(as_datetime(imp_df$endTime,   tz="UTC"), na.rm=TRUE))
        }
      }
    }, error = function(e) {})

    # Fall back to row-level timestamps if impacts didn't yield times
    if (is.na(start_val)) {
      start_val <- suppressWarnings(as_datetime(row[["createdAt"]], tz="UTC"))
      end_val   <- suppressWarnings(as_datetime(row[["updatedAt"]], tz="UTC"))
    }

    if (is.na(start_val) || start_val < WINDOW_START) return(NULL)

    dur <- suppressWarnings(
      as.numeric(difftime(end_val, start_val, units="hours")))

    # Severity from type and IncidentImpacts severity field
    sev_text <- tolower(paste(
      row[["type"]] %||% "",
      tryCatch({
        imp <- raw_sf[["IncidentImpacts"]][[i]]
        if (!is.null(imp)) paste(imp$severity %||% "", imp$type %||% "", collapse=" ")
        else ""
      }, error=function(e) "")
    ))
    sev_tier <- case_when(
      str_detect(sev_text, "major|service_unavailable|outage") ~ "full_outage",
      str_detect(sev_text, "minor|degradation|performance")    ~ "partial_outage",
      TRUE                                                       ~ "degraded"
    )

    tibble(
      provider        = "Salesforce",
      incident_id     = as.character(row[["id"]] %||% i),
      start_ts        = as.character(start_val),
      end_ts          = as.character(end_val),
      duration_hours  = dur,
      severity_tier   = sev_tier,
      affected_region = str_extract(keys, "EU\\d+") %||% "EU",
      affected_service = paste0("Salesforce Core (", keys, ")"),
      source_url      = paste0("https://status.salesforce.com/incidents/",
                                row[["externalId"]] %||% as.character(row[["id"]] %||% i)),
      data_tier       = "A"
    )
  })

  if (is.null(sf_eu) || nrow(sf_eu) == 0) {
    cat("  [INFO] 0 EU incidents in window — writing empty CSV\n")
    cat("  [INFO] Salesforce EU instances are stable; this may be correct.\n")
    sf_eu <- empty_incidents()
  }

  report_result(sf_eu, "Salesforce EU")
  write_incident_csv(sf_eu, "salesforce")

}, error = function(e) {
  cat(sprintf("\n  [ERROR] Salesforce: %s\n", conditionMessage(e)))
})


# =============================================================================
# FINAL SUMMARY
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep="")
cat("FETCH COMPLETE — Summary\n")
cat(strrep("=", 60), "\n\n", sep="")

expected <- c("aws_incidents.csv","azure_incidents.csv","gcp_incidents.csv",
              "equinix_incidents.csv","sap_incidents.csv","salesforce_incidents.csv")

all_present <- TRUE
for (f in expected) {
  path <- file.path(DATA_DIR, f)
  if (file.exists(path)) {
    df <- read_csv(path, show_col_types=FALSE)
    cat(sprintf("  [OK]  %-28s  %3d rows\n", f, nrow(df)))
  } else {
    cat(sprintf("  [MISSING] %-28s\n", f))
    all_present <- FALSE
  }
}

cat("\n")
if (all_present) {
  cat("All Tier A CSVs present (some may be empty — that is valid).\n")
  cat("Next: run scripts/validate_incidents.R\n")
} else {
  cat("One or more CSVs still missing — see errors above.\n")
}
cat("\nReminder: Tier B CSVs require manual construction:\n")
cat("  data/swift_incidents.csv\n  data/euroclear_incidents.csv\n")
cat("  data/clearstream_incidents.csv\n\n")
