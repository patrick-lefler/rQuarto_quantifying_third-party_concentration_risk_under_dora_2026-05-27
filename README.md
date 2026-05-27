# Operational Resilience: Quantifying Third-Party ICT Concentration Risk Under DORA

> A dependency graph model that translates a DORA Register of Information into a
> board-level business interruption loss distribution for a mid-market EU asset manager.

**Author:** Patrick Lefler
**Published:** 2026-05-27
**Rendered:** 

---

## Introduction

A network-based VaR model that quantifies ICT third-party concentration risk under DORA Article 28, calibrated to the ESAs' 19 designated Critical ICT Third-Party Providers (November 2025). The model shows that 8 vendor entries in a representative firm's Register of Information collapse to 5 independent failure domains — a structural finding the Register's concentration flags cannot express — and converts that structure into an annualized business interruption loss distribution in euros.

---

## Overview

The model constructs a directed ICT dependency graph for a €35B AUM EU-domiciled UCITS and AIF asset manager, mapping both direct contractual relationships and sub-outsourcing chains as required by DORA RTS 2025/532. Outage frequency distributions are parameterized from 36-month public incident histories of Tier A providers (AWS, Azure, GCP, Equinix, SAP Cloud, Salesforce EU) and manually reconstructed incident logs for Tier B providers (SWIFT, Euroclear, Clearstream). A Gaussian copula captures correlated failures within the cloud infrastructure cluster (AWS, Azure, Equinix) and the settlement cluster (SWIFT, Euroclear). A discrete-event simulation over 100,000 trials produces a full annualized business interruption loss (BIL) distribution, decomposed into direct revenue impact and DORA Article 19 regulatory notification costs. The gap between the naive independent-vendor VaR and the correlated network VaR is the quantitative cost of treating the Register as a sufficient risk management tool.

---

## Tech Stack

| Component | Detail |
|---|---|
| **Language** | R |
| **Framework** | [Quarto](https://quarto.org/) |
| **Network modeling** | `igraph`, `tidygraph`, `ggraph` |
| **Simulation** | `simmer`, `mc2d`, `copula` |
| **Visualization** | `ggplot2`, `plotly`, `patchwork` |
| **Tables** | `kableExtra` |
| **Output** | Self-contained HTML (`embed-resources: true`) |

---

## Repository Structure

```
dora-concentration-risk/
├── data/
│   ├── aws_incidents.csv          # Tier A — AWS EU RSS feed (0 rows, quiet window)
│   ├── azure_incidents.csv        # Tier A — Azure Atom feed + PPIR seed rows
│   ├── gcp_incidents.csv          # Tier A — GCP incidents.json
│   ├── equinix_incidents.csv      # Tier A — Equinix Statuspage seed rows
│   ├── sap_incidents.csv          # Tier A — SAP Trust Center seed rows
│   ├── salesforce_incidents.csv   # Tier A — Salesforce Trust API
│   ├── swift_incidents.csv        # Tier B — swift.com disclosures
│   ├── euroclear_incidents.csv    # Tier B — ECB FMI oversight reports
│   ├── clearstream_incidents.csv  # Tier B — Bundesbank payment oversight reports
│   ├── dependency_graph.csv       # ICT edge list — source of truth for graph
│   ├── parameters.csv             # All simulation parameters — single source of truth
│   ├── graph.rds                  # Pre-built igraph object for index.qmd
│   ├── node_attributes.csv        # Node metadata for ggraph visualisation
│   ├── failure_domains.csv        # Failure domain analysis output
│   └── ctpp_impact.csv            # CTPP impact set for concentration decomposition
├── scripts/
│   ├── fetch_incidents.R          # Pulls and caches Tier A incident histories
│   ├── validate_incidents.R       # Validates all incident CSVs; gates index.qmd
│   └── build_graph.R              # Constructs igraph object; computes failure domains
├── _brand.yml                     # Brand configuration
├── _quarto.yml                    # Project-level Quarto configuration
├── INSTRUCTIONS.md                # Project standards and model specification
└── index.qmd                      # Main Quarto entry point
```

---

## Methodology

**Data pipeline.** Incident histories are collected via three mechanisms: live JSON and RSS feeds for hyperscale cloud providers (Tier A), manual reconstruction from ECB and Bundesbank annual oversight reports and trade press for financial infrastructure providers (Tier B), and structured assumptions with documented rationale for providers with no public incident disclosure (structured). Every parameter is traceable to a named source in `data/parameters.csv`.

**Graph construction.** The ICT dependency graph is built as a directed acyclic graph in `igraph`, with edges pointing from the dependent node toward the dependency. Sub-outsourcing chains — TradeSaaS depending on AWS, the regulatory reporting platform depending on Azure — are encoded as second-tier edges, making the hidden CTPP dependencies visible in the graph structure and propagating correctly through the simulation.

**Simulation.** Three sequential layers convert the dependency graph into a loss distribution. The frequency layer draws correlated Poisson outage counts per CTPP using a Gaussian copula. The propagation layer traverses the reversed graph from each affected CTPP to identify all impaired firm services, using `igraph::subcomponent()` for performance at 100,000 trials. The severity layer applies log-normal duration draws, a settlement-window timing multiplier, and a DORA Article 19 regulatory cost layer to produce per-incident BIL in euros.

---

## Key Findings

> [To be completed after confirmed clean build. Three findings, each one sentence, each including a specific number from the rendered output.]
>
> Candidate findings based on model structure:
> - The firm's 8-vendor Register of Information collapses to 5 independent failure domains, a 1.6× concentration ratio the Register's vendor count cannot express.
> - The VaR 99 under the correlated base case (θ = 0.35) is €X.XM — approximately X.Xx the naive independent-vendor estimate, quantifying the cost of treating the Register as sufficient.
> - AWS is the single largest VaR 99 contributor (€X.XM), driven by the sub-outsourced TradeSaaS dependency that doubles its failure domain's service impact without appearing as a concentration flag in the Register.

---

## Script Execution Order

Run in sequence before rendering `index.qmd`:

```r
# 1. Pull Tier A incident histories
source("scripts/fetch_incidents.R")

# 2. Manually complete Tier B CSVs:
#    data/swift_incidents.csv
#    data/euroclear_incidents.csv
#    data/clearstream_incidents.csv

# 3. Validate all incident data — resolve all FAILs before proceeding
source("scripts/validate_incidents.R")

# 4. Build dependency graph and compute failure domains
source("scripts/build_graph.R")

# 5. Populate data/parameters.csv using lambda estimates
#    from validate_incidents.R output

# 6. Render
quarto render index.qmd
```

---

## Data Sources

| Provider | Source | Tier |
|---|---|---|
| AWS | status.aws.amazon.com RSS feeds | A |
| Azure | azure.status.microsoft Atom feed + Microsoft PPIRs | A |
| GCP | status.cloud.google.com/incidents.json | A |
| Equinix | equinixstatus.com Statuspage API | A |
| SAP Cloud | api.status.sap.com / SAP Trust Center | A |
| Salesforce EU | api.status.salesforce.com/v1/incidents | A |
| SWIFT | swift.com public disclosures | B |
| Euroclear | ECB annual FMI oversight reports | B |
| Clearstream | Deutsche Bundesbank payment oversight reports | B |
| CTPP list | ESAs Joint Oversight Committee, 18 November 2025 | Reference |

---

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

## Contact

Patrick Lefler — [LinkedIn](https://www.linkedin.com/in/patricklefler/) | [patricklefler.github.io](https://patricklefler.github.io) | [Substack](https://substack.com/@pflefler)
