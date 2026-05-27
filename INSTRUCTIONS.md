# Operational Resilience: Quantifying Third-Party ICT Concentration Risk Under DORA — Project Instructions

## 1. Project Overview

- **Short description:** A network-based loss model that converts ICT third-party concentration risk from a regulatory disclosure exercise into a financially quantified Value-at-Risk figure for a mid-market EU asset manager, calibrated to the ESAs' November 2025 list of designated Critical ICT Third-Party Providers.

- **Description:** DORA Article 28 requires financial entities to assess concentration risk in their ICT third-party arrangements, but the regulation specifies the obligation, not the method. Most institutions discharge the requirement through the Register of Information — a structured disclosure — without producing a financial loss figure the board can use for capital, insurance, or contractual decisions. This project builds a discrete-event simulation of a representative mid-market EU asset manager's ICT dependency graph, populates it with outage frequency and recovery time distributions drawn from public service-health histories of the ESAs' 19 designated Critical ICT Third-Party Providers (CTPPs), and produces an annualized business interruption loss distribution expressed in euros. The output reframes the Register of Information's concentration flags in the same unit of account as the firm's other risk exposures: a loss curve with VaR figures at the 95th and 99th percentiles, decomposed by failure mode and concentration cluster.

- **Abstract:** [To be written at document completion. Target: 200 words. Must address: the qualitative-to-quantitative translation; the network model's structural contribution over vendor-count metrics; the November 2025 CTPP designation list as the empirical anchor; the VaR output and its decision relevance for board-level capital and insurance discussions. No banned vocabulary. No bullet points.]

- **Target audience:** CROs, CIOs, and boards of EU financial entities subject to DORA; secondarily, US institutions subject to OCC third-party risk guidance and FFIEC cloud computing expectations.

- **Output format:** HTML, self-contained (`embed-resources: true`)

- **Render command:** `quarto render index.qmd`

- **Expected output path:** `index.html`

- **Data sources:**

  | Source | File | Origin | Tier |
  |--------|------|---------|------|
  | ESAs CTPP designation list | `data/ctpp_list.csv` | ESAs Joint Oversight Committee, 18 Nov 2025 | Reference |
  | AWS EU incident history | `data/aws_incidents.csv` | status.aws.amazon.com JSON feed | A |
  | Azure EU incident history | `data/azure_incidents.csv` | status.azure.com JSON feed | A |
  | GCP EU incident history | `data/gcp_incidents.csv` | status.cloud.google.com JSON feed | A |
  | Equinix EU facility incidents | `data/equinix_incidents.csv` | equinixstatus.com | A |
  | SAP Cloud EU incidents | `data/sap_incidents.csv` | sap.com/about/trust-center/cloud-service-status.html | A |
  | Salesforce EU incidents | `data/salesforce_incidents.csv` | status.salesforce.com (EU15, EU25, EU28) | A |
  | SWIFT incidents | `data/swift_incidents.csv` | swift.com disclosures + trade press reconstruction | B |
  | Euroclear incidents | `data/euroclear_incidents.csv` | ECB FMI oversight reports + trade press | B |
  | Clearstream incidents | `data/clearstream_incidents.csv` | Bundesbank payment oversight reports + trade press | B |
  | Asset manager dependency graph | `data/dependency_graph.csv` | Synthetic — parameterized to UCITS/AIF firm profile | Synthetic |
  | Model parameters | `data/parameters.csv` | Derived from above; single source of truth for simulation | Derived |

- **Project status:** [ ] In Progress / [ ] Complete / [ ] Archived

---

## 2. Directory Structure

```
dora-concentration-risk/
├── data/                    # Raw incident histories, dependency graph, parameters
│   ├── aws_incidents.csv
│   ├── azure_incidents.csv
│   ├── gcp_incidents.csv
│   ├── equinix_incidents.csv
│   ├── sap_incidents.csv
│   ├── salesforce_incidents.csv
│   ├── swift_incidents.csv
│   ├── euroclear_incidents.csv
│   ├── clearstream_incidents.csv
│   ├── ctpp_list.csv
│   ├── dependency_graph.csv
│   └── parameters.csv
├── scripts/
│   ├── fetch_incidents.R    # Pulls and caches Tier A JSON feeds
│   ├── build_graph.R        # Constructs igraph object from dependency_graph.csv
│   └── pipeline_diagnostic.R  # Row-count tracing outside Quarto message suppression
├── output/                  # Rendered HTML
├── _brand.yml               # Brand configuration
├── _quarto.yml              # Project-level Quarto configuration
├── INSTRUCTIONS.md          # This file
└── index.qmd                # Main Quarto entry point
```

---

## 3. Document Sections — Required and Ordered

| # | Section | Purpose | Constraints |
|---|---------|---------|-------------|
| 3.1 | Setup | Libraries, brand colors, `theme_brand()` definition | Echo false; no visible output |
| 3.2 | Introduction | Regulatory framing, the qualitative-label problem, why a network model | 3–4 paragraphs; lead with the non-obvious insight |
| 3.3 | The DORA Concentration Risk Framework | Maps Article 28 and RTS 2025/532 requirements onto model components | Includes the CTPP reference table (Table 1); one prose paragraph per sub-section |
| 3.4 | The Dependency Network | Defines the hypothetical asset manager; builds and renders the directed dependency graph | Network visualization required (ggraph); prose description of the firm's ICT footprint |
| 3.5 | Data and Parameter Calibration | Documents all incident data sources, derivation methodology, data tier flags, and uncertainty bounds | Includes the full parameter table (Table 2); explicit Tier A / B / Synthetic attribution for every row |
| 3.6 | The Loss Model | Three-layer model: frequency, propagation, severity; documents all distributional choices | Math typeset in MathJax; code visible; parallel structure to ransomware project's loss model section |
| 3.7 | Results | Base-case VaR table; concentration decomposition by CTPP; naive-vs-correlated comparison chart | VaR table (Table 3); two to three figures; the naive-vs-correlated gap is the headline chart |
| 3.8 | Sensitivity Analysis | Three named sensitivities with board-relevant interpretation | One figure per sensitivity scenario |
| 3.9 | Insights and Conclusion | Four to five insights as prose; conclusion paragraph | 300–400 words for insights; 150–200 words for conclusion; no bullet points |
| 3.10 | References | All cited sources with access dates | Numbered, consistent with ransomware project format |
| 3.11 | Session Information | `sessioninfo::session_info()` | `echo: false` |
| 3.12 | Footer | Rendered with Quarto + package attribution | Standard one-line format |

---

## 4. YAML Header

Every deliverable opens with this block verbatim. Do not alter structure, engine, or format options without explicit instruction.

```yaml
---
title: "Operational Resilience: Quantifying Third-Party ICT Concentration Risk Under DORA"
subtitle: "Translating the Register of Information into a Board-Level Loss Distribution"
author: "Patrick Lefler"
abstract: |
  [Abstract goes here — see Section 1 constraints]
date: [explicit date string "YYYY-MM-DD" to be added by author after confirmed clean build]
format:
  html:
    code-fold: true
    code-copy: true
    code-overflow: wrap
    code-tools: false
    code-summary: "Display code"
    df-print: kable
    embed-math: true
    embed-resources: true
    fig-align: center
    fig-height: 6
    fig-width: 10
    highlight-style: arrow
    lightbox: true
    linkcolor: "#0166CC"
    number-sections: false
    page-layout: full
    smooth-scroll: true
    theme: sandstone
    toc: true
    toc-depth: 3
    toc-location: right
    toc-title: "Contents"
execute:
  echo: true
  warning: false
  message: false
html-math-method: mathjax
knitr:
  opts_chunk:
    comment: "#>"
---
```

---

## 5. Brand and Theme Configuration

- Confirm `_brand.yml` is present in root before render.

**`_brand.yml` color block:**

```yaml
color:
  palette:
    grey: "#E5E5E5"
    dark-grey: "#222222"
    date-grey: "#6E6E73"
    white: "#FFFFFF"
    off-white: "#FEFEFA"
    white-smoke: "#F5F5F5"
    link-blue: "#0166CC"
    sandstone: "#EAE5DD"
  foreground: dark-grey
  background: white
typography:
  fonts:
    - family: Roboto
      source: google
      weight: [300, 400, 500]
      style: normal
    - family: Space Mono
      source: google
  base:
    family: Roboto
    weight: 400
  headings:
    family: Roboto
    color: dark-grey
    weight: 500
  monospace: Space Mono
```

**Setup chunk — brand color variables (identical to ransomware project):**

```r
brand_primary   <- "#1A1A2E"
brand_secondary <- "#16213E"
brand_accent    <- "#0F3460"
brand_highlight <- "#E94560"
brand_surface   <- "#F5F5F5"
brand_text      <- "#1A1A2E"

brand_palette <- c(
  primary   = brand_primary,
  secondary = brand_secondary,
  accent    = brand_accent,
  highlight = brand_highlight
)
```

**`theme_brand()` definition:** Copy verbatim from `finbert_model_audit.qmd` or `index.qmd` (ransomware project). No changes to the function body.

---

## 6. Visualization Rules

- Default stack: `ggplot2` → `ggplotly()` → `plotly` direct (in that priority order).
- `scale_fill_manual` / `scale_color_manual` applied throughout using `brand_palette`.
- **Network graph:** `ggraph` with `tidygraph` for the dependency visualization. Layout: `layout = "sugiyama"` for the directed acyclic graph (firm at root, CTPPs as terminal nodes). Node color encodes CTPP designation tier (designated vs. non-designated dependency). Edge width encodes dependency criticality (critical-or-important function vs. non-CIF).
- **Loss distributions:** `ggplot2` density plots wrapped in `ggplotly()`, consistent with ransomware project's sensitivity chart style.
- **Concentration decomposition:** Horizontal bar chart (provider on y-axis, VaR contribution in euros on x-axis), `brand_highlight` fill for the top contributor, `brand_accent` for the remainder.
- **Naive vs. correlated comparison:** Overlaid density plots using `brand_secondary` (naive/independent) and `brand_highlight` (correlated), matching the ransomware sensitivity chart's visual grammar.

---

## 7. Table Rules

- Default: `kable` + `kableExtra` → `gt` → `DT::datatable()`.
- `DT::datatable()` only when explicitly requested.

**Default `kable` setup:**

```r
kable(
  data,
  format    = "html",
  digits    = 3,
  caption   = "Table N: [Description]",
  col.names = c("Col 1", "Col 2", "Col 3")
) |>
  kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width        = TRUE,
    position          = "left",
    font_size         = 13
  )
```

**Project-specific table conventions:**

- **Table 1 (CTPP Reference Table):** 19 rows, columns: Provider / Category / Primary Services / Lead Overseer / Data Tier / In-Scope for Asset Manager Model. Highlight in-scope rows with `row_spec()`.
- **Table 2 (Parameter Table):** One row per calibrated parameter, columns: Parameter ID / Provider / Description / Value / Distribution / Source / Data Tier. Bold every Tier B row. Include a footer note explaining the Tier A / B / Synthetic distinction.
- **Table 3 (VaR Summary):** Identical structure to the ransomware project's Table 3. Rows: Mean / Median / VaR 75 / VaR 95 / VaR 99. Columns: Metric / Total BIL / Direct Revenue Loss / Regulatory and Legal. Highlight VaR 95 and VaR 99 rows.

---

## 8. R Libraries

```r
# --- Default libraries (all projects) ---
library(kableExtra)   # Table formatting
library(knitr)        # Document rendering
library(plotly)       # Interactive chart wrapping
library(scales)       # Axis and label formatting
library(sessioninfo)  # Session provenance
library(tidyverse)    # Data manipulation and ggplot2

# --- Project-specific libraries ---
library(igraph)       # Dependency network construction and graph traversal
library(tidygraph)    # Tidy interface to igraph for ggraph compatibility
library(ggraph)       # Network visualization in ggplot2 grammar
library(simmer)       # Discrete-event simulation of outage propagation through the graph
library(mc2d)         # Two-dimensional Monte Carlo for frequency and duration layers
library(copula)       # Correlated Poisson draws across CTPPs via Gaussian copula
library(jsonlite)     # Parsing Tier A JSON status feeds (AWS, GCP)
library(httr2)        # HTTP requests for status page feeds
library(lubridate)    # Date-time parsing for incident timestamp normalization
library(patchwork)    # Multi-panel figure composition
```

Do not remove default libraries unless genuinely unused in the final document. Add no libraries beyond the above without updating this file first.

---

## 9. Data Pipeline Specification

### 9.1 Tier A data ingestion (`scripts/fetch_incidents.R`)

The fetch script runs outside Quarto and caches results to `data/`. It is not embedded in `index.qmd`. This follows the `pipeline_diagnostic.R` pattern established in the LSTM project: pipeline verification happens outside Quarto's `message: false` suppression.

**AWS:** `https://status.aws.amazon.com/data.json` — parse with `jsonlite::fromJSON()`, filter to EU regions (`eu-west-1`, `eu-west-2`, `eu-central-1`, `eu-south-1`), retain incidents from the 36-month rolling window ending at project build date.

**Azure:** `https://azure.status.microsoft/en-us/status/feed/` (Atom feed) — parse with `xml2::read_xml()`, filter to European region incidents.

**GCP:** `https://status.cloud.google.com/incidents.json` — parse with `jsonlite::fromJSON()`, filter to `europe-west` and `europe-north` regions.

**Equinix:** `https://equinixstatus.com/api/v2/incidents.json` — parse with `jsonlite::fromJSON()`, filter to IBX facilities in Frankfurt (FR2, FR5), Amsterdam (AM1, AM3), London (LD5, LD8), Dublin (DB1).

**SAP / Salesforce:** HTML status pages; use `httr2` + `rvest` to scrape incident tables. Cache raw HTML alongside parsed CSV for reproducibility audit.

**Incident classification:** After ingestion, classify each incident into one of three severity tiers based on title/description text using a keyword lookup table stored in `data/severity_keywords.csv`:
- `full_outage` — "unavailable", "outage", "down", "offline"
- `partial_outage` — "degraded", "partial", "intermittent", "impaired"
- `degraded` — "elevated", "latency", "slow", "performance"

**Output schema for all incident CSVs** (uniform across all providers):

```
provider, incident_id, start_ts, end_ts, duration_hours, severity_tier,
affected_region, affected_service, source_url, data_tier
```

### 9.2 Tier B manual incident logs

SWIFT, Euroclear, and Clearstream incident CSVs are manually constructed and committed to `data/`. Each row must include `source_url` pointing to the specific disclosure document or trade press article. A `notes` column documents any inference made about duration or scope not directly stated in the source. The calibration section of `index.qmd` must cite the row count and date range for each Tier B log explicitly.

### 9.3 Dependency graph (`data/dependency_graph.csv`)

Defines the hypothetical asset manager's ICT footprint as a directed edge list.

**Schema:**

```
from_node, to_node, edge_type, criticality, sub_outsourcing_tier,
service_category, ctpp_designated, notes
```

**`edge_type` values:** `direct` (firm → vendor), `sub_outsourced` (vendor → CTPP they run on)

**`criticality` values:** `CIF` (Critical or Important Function per DORA Article 3), `non_CIF`

**`service_category` values:** `cloud_infrastructure`, `market_data`, `order_management`,
`settlement_custody`, `regulatory_reporting`, `network_connectivity`

**Representative firm profile (€25-50B AUM, UCITS/AIF, EU-domiciled):**

| Service Category | Vendor | Underlying CTPP | Tier |
|------------------|--------|-----------------|------|
| Cloud infrastructure | AWS (direct) | AWS | A |
| Cloud infrastructure | Azure (direct) | Azure | A |
| Order management / EMS | Trading SaaS vendor (runs on AWS) | AWS (sub-outsourced) | A |
| Market data | Bloomberg (non-designated) | — | Non-CTPP |
| Settlement / custody | Direct Euroclear member | Euroclear | B |
| Regulatory reporting | SaaS reporting platform (runs on Azure) | Azure (sub-outsourced) | A |
| Network connectivity | Co-location at Equinix FR2 | Equinix | A |
| Interbank messaging | SWIFT direct participant | SWIFT | B |

This dependency graph is the document's single most important structural element. It is what allows the model to show that 8 vendor entries collapse to 5 independent failure domains (AWS cluster, Azure cluster, Euroclear, SWIFT, Equinix), producing a 1.6x concentration ratio. EUROCLEAR and SWIFT are structurally separate domains in the graph — each a distinct terminal node with no shared upstream dependency — but are correlated in the simulation's frequency layer via a Gaussian copula (`COPULA_THETA_SETTLEMENT`) to capture shared settlement-cycle timing exposure. The true correlated VaR is materially higher than the naive independent-vendor VaR.

### 9.4 `data/parameters.csv` — single source of truth

One row per simulation parameter. No numeric values are hardcoded in `index.qmd`; all are read from this file via a `get_param()` helper function (identical pattern to the ransomware project).

**Required columns:**

```
parameter_id, provider, description, value_numeric, distribution,
source_citation, data_tier, uncertainty_note
```

**Mandatory rows:**

| parameter_id | Description |
|---|---|
| `MC_TRIALS` | Number of simulation trials (default: 100,000) |
| `MC_SEED` | Random seed |
| `AWS_LAMBDA` | Poisson rate — major EU outages per year |
| `AZURE_LAMBDA` | Poisson rate — major EU outages per year |
| `GCP_LAMBDA` | Poisson rate — major EU outages per year |
| `EQUINIX_LAMBDA` | Poisson rate — major EU facility outages per year |
| `SWIFT_LAMBDA` | Poisson rate — major messaging disruptions per year |
| `EUROCLEAR_LAMBDA` | Poisson rate — major settlement outages per year |
| `{PROVIDER}_DUR_P50` | Median outage duration in hours |
| `{PROVIDER}_DUR_P90` | 90th percentile outage duration in hours |
| `BIL_RATE_AUM` | Business interruption loss rate (€ per hour per €1B AUM) |
| `REGULATORY_COST_P50` | Median regulatory notification and remediation cost per incident |
| `REGULATORY_COST_P90` | 90th percentile regulatory cost |
| `COPULA_THETA` | Gaussian copula correlation parameter for AWS/Azure/Equinix cluster |

---

## 10. Model Specification

### 10.1 Frequency layer

Each in-scope CTPP draws independently from `rpois(1, lambda)` in each simulation trial, where lambda is the annualized major-incident rate from the calibrated parameter table. The dependency graph then maps each CTPP outage to the set of firm-level services it disrupts. A CTPP with no outage in a given trial contributes zero service disruptions regardless of dependency structure.

Correlated draws for the AWS / Azure / Equinix cluster — which share physical co-location exposure and, for some events, common internet routing dependencies — are generated using a Gaussian copula via the `copula` package. The copula correlation parameter (`COPULA_THETA`) is a documented assumption, not empirically derived; it is flagged as a primary sensitivity parameter. SWIFT and Euroclear are treated as independent of the cloud cluster (different failure modes and different operational geographies) but correlated with each other through shared settlement-cycle timing dependencies. This correlation is modeled with a second copula block.

### 10.2 Propagation layer

For each simulated CTPP outage, the `igraph` dependency graph is traversed from the outage node toward the firm (root), identifying all firm-level services that depend on the affected CTPP either directly or through sub-outsourcing chains. A service is marked "impaired" if any node in its dependency path is experiencing an outage in that trial. The propagation logic is implemented as a single `igraph::subcomponent()` call on the reversed graph, not as a loop — this is important for performance at 100,000 trials.

### 10.3 Severity layer

Business interruption loss (BIL) per impaired service per outage is a function of:

1. **Outage duration** — drawn from the provider's log-normal duration distribution (parameterized from `{PROVIDER}_DUR_P50` and `{PROVIDER}_DUR_P90`).
2. **Service criticality** — CIF services contribute full BIL; non-CIF services contribute 25% of BIL rate (documented multiplier, not derived).
3. **Time-of-window** — outages during settlement windows (09:00–17:30 CET) are given 1.5× the BIL rate of off-hours outages. The settlement window probability is parameterized from a uniform draw over a 24-hour cycle.
4. **Regulatory cost** — each incident meeting the DORA Article 19 major-incident threshold (duration > 4 hours for a CIF service, or > 2 hours for payment services) triggers a regulatory notification and remediation cost draw from the `REGULATORY_COST` log-normal distribution.

Annual total BIL in each trial is the sum of per-incident BIL and regulatory costs across all impaired services.

The back-solve for log-normal parameters from two percentile anchors uses the same closed-form equations as the ransomware project (typeset in MathJax, same notation). Do not re-derive; copy the equations and update the variable names.

---

## 11. Writing Standards

All standards from the project template apply without modification. Project-specific additions and reminders:

**Voice and structure:** Third person, direct, precise. Lead with the non-obvious insight. One idea per paragraph. No bullet-point dumps. No em-dash overuse.

**Banned vocabulary:** Full list from template applies. Additional project-specific prohibitions: "ecosystem" (except in biological context), "landscape" (as metaphor), "holistic," "robust" (except in specific statistical regression context). Do not use "resilience" as a vague positive attribute — use it only when referring specifically to DORA's defined concept of digital operational resilience.

**Regulatory citations:** Cite DORA articles by number on first reference (e.g., "DORA Article 28"). On subsequent references within the same section, "Article 28" is sufficient. Always cite the specific RTS or ITS designation (e.g., "RTS 2025/532") rather than a generic reference to "the subcontracting RTS."

**Proper nouns and acronyms — use consistently:**
- DORA (not "the regulation" or "the Act" after first use)
- CTPP (not "critical provider" or "critical third party")
- CIF (Critical or Important Function — spell out on first use only)
- BIL (Business Interruption Loss — define on first use)
- ALE (Annualized Loss Expectancy — consistent with ransomware project; use only if directly comparing to that project's output)
- VaR (not "Value at Risk" after first definition)
- ESAs (European Supervisory Authorities — spell out on first use)
- JOC (Joint Oversight Committee — spell out on first use)
- Register of Information (always capitalized; it is a defined regulatory artifact)

**Number formatting:** Consistent with template. Euro amounts: €X,XXX format (not $). Percentages: one decimal place. Durations: hours to one decimal place (e.g., 4.2 hours, not "four hours"). VaR figures: reported to one decimal place in euros millions (e.g., €8.4M).

**Figures and tables:** Captions add information; they do not repeat axis labels. Every figure caption must contain at least one claim about what the data shows that is not already obvious from the chart title. Every table caption must state the source or derivation basis.

**Key Takeaways:** Written as prose paragraphs, not bullet points. Each takeaway identifies a board-relevant decision implication, not a methodological observation. The structure from the ransomware project's Insights section is the template — lead with the finding, then explain the decision implication.

---

## 12. Deliverables Checklist

- [ ] `index.qmd` — primary rendered document
- [ ] `_brand.yml` — confirmed in root
- [ ] `scripts/fetch_incidents.R` — Tier A data pipeline, confirmed running
- [ ] `scripts/build_graph.R` — dependency graph construction, confirmed running
- [ ] `data/parameters.csv` — all rows populated, all sources cited
- [ ] `data/dependency_graph.csv` — confirmed consistent with Section 9.3 schema
- [ ] Tier B incident CSVs — SWIFT, Euroclear, Clearstream — manually constructed and committed
- [ ] `README.md` — complete
- [ ] Abstract — embedded in YAML, 150–200 words
- [ ] Output HTML — confirmed self-contained (`embed-resources: true`)
- [ ] LinkedIn post (if requested)

---

## 13. README.md Template

```markdown
# Operational Resilience: Quantifying Third-Party ICT Concentration Risk Under DORA

> Translating the EU Register of Information into a board-level business interruption
> loss distribution for a mid-market asset manager.

**Author:** Patrick Lefler
**Published:** [date]
**Rendered:** [leave blank]

## Introduction

A network-based VaR model that quantifies ICT third-party concentration risk under
DORA Article 28, calibrated to the ESAs' 19 designated Critical ICT Third-Party
Providers (November 2025).

## Overview

This project builds a discrete-event simulation of a representative EU asset manager's
ICT dependency graph to produce an annualized business interruption loss distribution
in euros. Outage frequency and duration distributions are parameterized from public
service-health histories of Tier A providers (AWS, Azure, GCP, Equinix, SAP Cloud,
Salesforce EU) and reconstructed incident logs for Tier B providers (SWIFT, Euroclear,
Clearstream). A Gaussian copula captures correlated failures within the cloud
infrastructure cluster. The model's central finding — that vendor-count concentration
metrics systematically understate true tail exposure when sub-outsourcing chains
collapse multiple vendors to a shared underlying provider — is quantified as a
euro-denominated gap between the naive independent-vendor VaR and the correlated
network VaR.

## Tech Stack

- **Language:** R
- **Framework:** [Quarto](https://quarto.org/)
- **Primary Libraries:** tidyverse, igraph, tidygraph, ggraph, simmer, mc2d, copula,
  ggplot2, kableExtra, plotly
- **Deployment / Output:** Self-contained HTML

## Repository Structure

```
dora-concentration-risk/
├── data/                    # Incident histories, dependency graph, parameters
├── scripts/                 # Data pipeline and graph construction scripts
├── output/                  # Rendered HTML
├── _brand.yml
├── _quarto.yml
├── INSTRUCTIONS.md
└── index.qmd
```

## Key Findings

> [To be completed after confirmed clean build. Three findings, each one sentence,
> each including a specific number from the results.]

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Contact

Patrick Lefler — [LinkedIn](https://www.linkedin.com/in/patricklefler/) |
[patricklefler.github.io] | [Substack](https://substack.com/@pflefler)
```

---

## 14. Open Issues and Decisions Log

`[2026-05-25]` — Data tier for Deutsche Telekom, Worldline, FIS, Fiserv, IBM, Oracle, Broadridge, and SIX Group: confirmed Tier B (manual reconstruction from SEC filings, ECB/Bundesbank oversight reports, trade press). These providers are outside the representative asset manager's dependency graph and are therefore excluded from the base-case simulation. They may be referenced in the DORA framework section when discussing the full 19-provider designation list.

`[2026-05-25]` — Bloomberg and LSEG: confirmed absent from the November 2025 CTPP designation list. Include in the dependency network visualization as non-designated critical dependencies. Discuss the non-designation in the introduction or framework section as a substantive observation about the Register of Information's coverage. Do not calibrate outage loss from these providers in the base-case simulation.

`[2026-05-25]` — Murex, Temenos, Finastra: confirmed exclusion from the outage simulation. Treat in a separate prose sub-section under Section 3.3 (DORA Framework) as correlated software vulnerability risk. No quantitative model for this sub-section.

`[2026-05-25]` — Copula correlation parameter (`COPULA_THETA`) for the AWS/Azure/Equinix cluster: no empirical basis for calibration. Document as a structured assumption. Include as a primary sensitivity parameter. Range: 0.0 (independent) to 0.8 (highly correlated); base case 0.35.

`[2026-05-25]` — Settlement window timing multiplier (1.5×): documented assumption. Flag as sensitivity parameter with a note that financial-sector firms have concentrated exposure during CET settlement hours.

`[2026-05-26]` — Failure domain count revised from 4 to 5. build_graph.R confirmed EUROCLEAR and SWIFT are structurally independent nodes in the dependency graph (separate terminal nodes, no shared upstream dependency). The original outline assumed a 4-domain result by treating them as a single settlement cluster. Decision (Option A): retain 5-domain graph structure; model settlement correlation via `COPULA_THETA_SETTLEMENT` in the frequency layer. Document's central claim updated to: 8 vendor entries, 5 failure domains, 1.6x concentration ratio. INSTRUCTIONS.md §9.3 and build_graph.R updated accordingly.

`[2026-05-25]` — BIL rate parameterization: no public benchmark for per-hour BIL at a €25-50B AUM asset manager exists. Derive from AUM-scaled management fee revenue (typical blended fee ~35-40bps annually). €35B AUM × 37.5bps / 8,760 hours ≈ €1,490/hour as the base-case BIL rate. Flag as sensitivity parameter.

---

## 15. Change Log

`[2026-05-26]` — Failure domain count corrected from 4 to 5 following confirmed build_graph.R output. Section 9.3 central claim updated. Open Issues log entry added. build_graph.R summary comment updated.

`[2026-05-25]` — Initial INSTRUCTIONS.md drafted. Data-source tiers confirmed through
working session. Model specification written. Dependency graph schema defined.
