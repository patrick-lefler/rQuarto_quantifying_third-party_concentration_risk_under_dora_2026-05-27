# =============================================================================
# validate_incidents.R  —  v2
# DORA Third-Party Concentration Risk Project
# -----------------------------------------------------------------------------
# Run after fetch_incidents.R and after completing Tier B CSVs manually.
#
# Pass / Warn / Fail logic:
#   PASS  — no action needed
#   WARN  — usable; document the limitation explicitly in index.qmd
#   FAIL  — genuine data gap; must be resolved before index.qmd
#
# Key design decisions vs v1:
#   - History window is measured against the OBSERVATION PERIOD
#     (WINDOW_START to now), not the span between first and last incident.
#     A provider with one incident still has a 36-month observation window.
#   - Incident count thresholds are recalibrated to reflect reality:
#     AWS, GCP, Equinix, Azure, and Salesforce are genuinely stable;
#     0–4 incidents over 36 months is the correct empirical signal.
#     Structured assumption is the documented fallback, not a FAIL.
#   - Empty CSVs (0 rows) are valid for stable providers and do not
#     trigger the placeholder check.
#   - "Must resolve" FAILs are reserved for: missing files, unparseable
#     data, placeholder rows not replaced, and negative durations.
#   - Thin data (low n, wide lambda CI) is a WARN with explicit
#     documentation requirement — not a blocker.
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

SCRIPT_DIR <- dirname(normalizePath(sys.frame(1)$ofile,
                                     winslash = "/",
                                     mustWork = FALSE))
if (!nzchar(SCRIPT_DIR) || SCRIPT_DIR == ".") {
  SCRIPT_DIR <- dirname(normalizePath("scripts/validate_incidents.R"))
}
DATA_DIR     <- file.path(SCRIPT_DIR, "..", "data")
WINDOW_START <- Sys.time() - lubridate::years(3)
WINDOW_YEARS <- 3.0    # observation period used for lambda estimation

REQUIRED_COLS <- c("provider", "incident_id", "start_ts", "end_ts",
                   "duration_hours", "severity_tier", "affected_region",
                   "affected_service", "source_url", "data_tier")

# ---------------------------------------------------------------------------
# Provider configuration
# ---------------------------------------------------------------------------
# min_incidents: FAIL below this (genuine data gap — structured assumption
#   is documented in parameters.csv and INSTRUCTIONS.md §9.4)
# warn_incidents: WARN below this (usable; lambda CI will be wide)
# structured_ok: TRUE = 0 incidents is acceptable; lambda from assumption
# ---------------------------------------------------------------------------
PROVIDERS <- tibble(
  slug              = c("aws","azure","gcp","equinix","sap",
                        "salesforce","swift","euroclear","clearstream"),
  display           = c("AWS","Azure","GCP","Equinix","SAP Cloud",
                        "Salesforce EU","SWIFT","Euroclear","Clearstream"),
  tier              = c("A","A","A","A","A","A","B","B","B"),
  min_incidents     = c( 0,  1,  0,  1,  1,  1,  1,  1,  1),
  warn_incidents    = c( 3,  5,  3,  3,  3,  3,  2,  2,  2),
  duration_required = c(TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,FALSE,FALSE,FALSE),
  structured_ok     = c(TRUE,FALSE,TRUE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE)
)

issues  <- list()
results <- list()

cat("\n", strrep("=", 65), "\n", sep = "")
cat("INCIDENT DATA VALIDATION REPORT  —  v2\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M UTC"), "\n")
cat(sprintf("Observation window: %s to %s (%.0f months)\n",
            format(WINDOW_START, "%Y-%m-%d"),
            format(Sys.time(),   "%Y-%m-%d"),
            WINDOW_YEARS * 12))
cat(strrep("=", 65), "\n\n", sep = "")

for (i in seq_len(nrow(PROVIDERS))) {
  p    <- PROVIDERS[i, ]
  path <- file.path(DATA_DIR, paste0(p$slug, "_incidents.csv"))
  cat(sprintf("--- %s (Tier %s) ---\n", p$display, p$tier))

  # CHECK 1: File exists
  if (!file.exists(path)) {
    cat(sprintf("  [FAIL] File missing: %s\n\n", basename(path)))
    issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                   msg="CSV file missing")))
    next
  }

  df <- tryCatch(
    read_csv(path, show_col_types=FALSE),
    error = function(e) {
      cat(sprintf("  [FAIL] Cannot read file: %s\n\n", conditionMessage(e)))
      issues <<- c(issues, list(list(provider=p$display, level="FAIL",
                                      msg=paste("Cannot parse CSV:", conditionMessage(e)))))
      NULL
    }
  )
  if (is.null(df)) next

  # CHECK 2: Schema conformance
  missing_cols <- setdiff(REQUIRED_COLS, names(df))
  if (length(missing_cols) > 0) {
    cat(sprintf("  [FAIL] Missing columns: %s\n", paste(missing_cols, collapse=", ")))
    issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                   msg=paste("Missing cols:", paste(missing_cols, collapse=", ")))))
  }
  extra_cols <- setdiff(names(df), c(REQUIRED_COLS, "notes"))
  if (length(extra_cols) > 0)
    cat(sprintf("  [INFO] Extra columns (harmless): %s\n", paste(extra_cols, collapse=", ")))

  # CHECK 3: Empty file — valid for structured-assumption providers
  if (nrow(df) == 0) {
    if (p$structured_ok) {
      cat(sprintf("  [PASS] 0 rows — lambda set via structured assumption (documented)\n"))
      cat(sprintf("         Add AWS_LAMBDA / GCP_LAMBDA to parameters.csv manually.\n"))
    } else {
      cat(sprintf("  [FAIL] 0 rows — at least %d incident(s) required\n", p$min_incidents))
      issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                     msg="0 rows — no incident data")))
    }
    cat("\n"); next
  }

  # CHECK 4: Placeholder rows (only meaningful for non-empty files)
  is_placeholder <- nrow(df) > 0 && all(str_detect(df$incident_id, "PLACEHOLDER"))
  if (is_placeholder) {
    cat("  [FAIL] Placeholder rows not replaced — manual completion required\n\n")
    issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                   msg="Placeholder rows not replaced")))
    next
  }

  # CHECK 5: Timestamp parsability
  ts_start <- suppressWarnings(as_datetime(df$start_ts, tz="UTC"))
  n_bad_ts <- sum(is.na(ts_start))
  if (n_bad_ts > 0) {
    cat(sprintf("  [WARN] %d rows with unparseable start_ts\n", n_bad_ts))
    issues <- c(issues, list(list(provider=p$display, level="WARN",
                                   msg=sprintf("%d unparseable start_ts", n_bad_ts))))
  }

  ts_valid <- ts_start[!is.na(ts_start)]
  if (length(ts_valid) == 0) {
    cat("  [FAIL] No valid timestamps\n\n")
    issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                   msg="No valid timestamps")))
    next
  }

  # CHECK 6: Observation window coverage
  # Use the full WINDOW_YEARS observation period for lambda estimation,
  # not the span between first and last incident (which is always short
  # for providers with few incidents).
  oldest <- min(ts_valid)
  newest <- max(ts_valid)

  # How much of the observation window do the incidents cover?
  # A single incident within the window = full 36-month observation period.
  incidents_in_window <- sum(ts_valid >= WINDOW_START)
  obs_months <- WINDOW_YEARS * 12

  if (incidents_in_window == 0) {
    cat(sprintf("  [FAIL] 0 incidents within the %d-month observation window\n",
                round(obs_months)))
    cat(sprintf("         Oldest incident: %s — outside window start %s\n",
                format(oldest, "%Y-%m-%d"), format(WINDOW_START, "%Y-%m-%d")))
    issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                   msg="No incidents within observation window")))
  } else {
    cat(sprintf("  [PASS] Observation window: %d months | %d incident(s) in window\n",
                round(obs_months), incidents_in_window))
    cat(sprintf("         Incident date range: %s – %s\n",
                format(oldest, "%Y-%m-%d"), format(newest, "%Y-%m-%d")))
  }

  # CHECK 7: Incident count — WARN only (thin data = wide CI, not a blocker)
  n <- nrow(df)
  if (n < p$min_incidents && p$min_incidents > 0) {
    cat(sprintf("  [FAIL] %d incidents — minimum %d required\n", n, p$min_incidents))
    issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                   msg=sprintf("Only %d incident(s) (min %d)", n, p$min_incidents))))
  } else if (n < p$warn_incidents) {
    cat(sprintf("  [WARN] %d incident(s) — lambda CI will be wide; document in index.qmd\n", n))
    issues <- c(issues, list(list(provider=p$display, level="WARN",
                                   msg=sprintf("Only %d incident(s); wide lambda CI", n))))
  } else {
    cat(sprintf("  [PASS] %d incidents\n", n))
  }

  # CHECK 8: Duration completeness
  if (p$duration_required) {
    n_na_dur   <- sum(is.na(df$duration_hours))
    n_neg_dur  <- sum(df$duration_hours < 0, na.rm=TRUE)
    n_zero_dur <- sum(df$duration_hours == 0, na.rm=TRUE)
    pct        <- (1 - n_na_dur / nrow(df)) * 100

    if (pct < 50) {
      cat(sprintf("  [FAIL] duration_hours: %.0f%% complete — log-normal fit not possible\n", pct))
      issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                     msg=sprintf("duration_hours %.0f%% complete", pct))))
    } else if (pct < 80) {
      cat(sprintf("  [WARN] duration_hours: %.0f%% complete — P50/P90 estimates uncertain\n", pct))
      issues <- c(issues, list(list(provider=p$display, level="WARN",
                                     msg=sprintf("duration_hours %.0f%% complete", pct))))
    } else {
      dur_vals <- df$duration_hours[!is.na(df$duration_hours) & df$duration_hours > 0]
      if (length(dur_vals) > 0) {
        cat(sprintf("  [PASS] duration_hours: %.0f%% complete | P50 %.1fh | P90 %.1fh\n",
                    pct, quantile(dur_vals, 0.50), quantile(dur_vals, 0.90)))
      } else {
        cat(sprintf("  [PASS] duration_hours: %.0f%% complete (all zero/NA after filter)\n", pct))
      }
    }
    if (n_neg_dur > 0) {
      cat(sprintf("  [FAIL] %d negative duration_hours — end_ts < start_ts\n", n_neg_dur))
      issues <- c(issues, list(list(provider=p$display, level="FAIL",
                                     msg=sprintf("%d negative durations", n_neg_dur))))
    }
    if (n_zero_dur > 0)
      cat(sprintf("  [WARN] %d zero-duration rows — verify end_ts parsing\n", n_zero_dur))
  } else {
    cat("  [INFO] duration_hours not required (Tier B) — structured assumption applies\n")
  }

  # CHECK 9: Severity distribution
  sev_counts <- table(df$severity_tier)
  cat(sprintf("  [INFO] Severity: %s\n",
              paste(names(sev_counts), sev_counts, sep="=", collapse=" | ")))

  invalid_sev <- df$severity_tier[!df$severity_tier %in%
                                    c("full_outage","partial_outage","degraded")]
  if (length(invalid_sev) > 0) {
    cat(sprintf("  [WARN] Unrecognised severity values: %s\n",
                paste(unique(invalid_sev), collapse=", ")))
    issues <- c(issues, list(list(provider=p$display, level="WARN",
                                   msg="Unrecognised severity_tier values")))
  }

  # CHECK 10: Implied Poisson lambda over the full observation window
  lambda_est <- incidents_in_window / WINDOW_YEARS
  lambda_se  <- sqrt(lambda_est / WINDOW_YEARS)
  cat(sprintf("  [INFO] Lambda (%.0f-month window): %.3f/yr [95%% CI: %.3f – %.3f]\n",
              obs_months,
              lambda_est,
              max(0, lambda_est - 1.96 * lambda_se),
              lambda_est + 1.96 * lambda_se))

  if (lambda_est > 10) {
    cat("  [WARN] Lambda > 10/yr — verify EU filter is not capturing minor notices\n")
    issues <- c(issues, list(list(provider=p$display, level="WARN",
                                   msg=sprintf("Lambda %.1f/yr seems high", lambda_est))))
  }

  if (n < p$warn_incidents) {
    cat("  [INFO] Wide CI expected — record structured assumption rationale\n")
    cat(sprintf("         in parameters.csv 'uncertainty_note' column.\n"))
  }

  cat("\n")
  results[[p$display]] <- list(
    n              = n,
    in_window      = incidents_in_window,
    lambda         = lambda_est,
    lambda_ci_low  = max(0, lambda_est - 1.96 * lambda_se),
    lambda_ci_high = lambda_est + 1.96 * lambda_se,
    passes         = sum(sapply(issues, function(x)
                           x$provider == p$display && x$level == "FAIL")) == 0
  )
}

# =============================================================================
# SUMMARY
# =============================================================================

cat(strrep("=", 65), "\n", sep="")
cat("VALIDATION SUMMARY\n")
cat(strrep("=", 65), "\n\n", sep="")

fails <- Filter(function(x) x$level == "FAIL", issues)
warns <- Filter(function(x) x$level == "WARN", issues)

if (length(fails) == 0 && length(warns) == 0) {
  cat("  ALL CHECKS PASSED — data pipeline ready for build_graph.R\n\n")
} else {
  if (length(fails) > 0) {
    cat(sprintf("  FAILS (%d) — resolve before index.qmd:\n", length(fails)))
    for (f in fails) cat(sprintf("    [FAIL] %-20s %s\n", f$provider, f$msg))
    cat("\n")
  }
  if (length(warns) > 0) {
    cat(sprintf("  WARNINGS (%d) — usable; document in Data & Calibration section:\n",
                length(warns)))
    for (w in warns) cat(sprintf("    [WARN] %-20s %s\n", w$provider, w$msg))
    cat("\n")
  }
}

# Lambda summary table — inputs to parameters.csv
cat(strrep("-", 65), "\n", sep="")
cat("LAMBDA ESTIMATES — for parameters.csv\n")
cat(strrep("-", 65), "\n", sep="")
cat(sprintf("  %-16s  %5s  %8s  %8s  %8s  %s\n",
            "Provider", "N", "Lambda", "CI Low", "CI High", "Note"))
for (nm in names(results)) {
  r <- results[[nm]]
  note <- if (r$lambda == 0) "structured assumption required"
          else if (r$n < 3)  "wide CI — document assumption"
          else                "empirical MLE"
  cat(sprintf("  %-16s  %5d  %8.3f  %8.3f  %8.3f  %s\n",
              nm, r$n, r$lambda, r$lambda_ci_low, r$lambda_ci_high, note))
}
cat("\n")

cat("Next step:\n")
if (length(fails) > 0) {
  cat("  Resolve FAILs above, then re-run validate_incidents.R\n")
  cat("  FAILs requiring manual data work:\n")
  for (f in fails) {
    if (str_detect(f$msg, "[Pp]laceholder|missing|0 row")) {
      cat(sprintf("    -> %s: %s\n", f$provider, f$msg))
    }
  }
} else {
  cat("  Run scripts/build_graph.R\n")
  cat("  Then populate data/parameters.csv using lambda estimates above\n")
}
cat("\n")
