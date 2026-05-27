# =============================================================================
# build_graph.R
# DORA Third-Party Concentration Risk Project
# -----------------------------------------------------------------------------
# Responsibilities:
#   1. Write data/dependency_graph.csv — the firm's ICT edge list
#   2. Construct an igraph object from that edge list
#   3. Validate the graph structure (connectivity, DAG property, node coverage)
#   4. Compute and print failure domain analysis — the headline finding
#   5. Save the graph object to data/graph.rds for use in index.qmd
#
# Run from project root AFTER validate_incidents.R passes:
#   setwd("/path/to/dora-concentration-risk")
#   source("scripts/build_graph.R")
#
# Required packages:
#   install.packages(c("igraph", "tidygraph", "tidyverse"))
#
# Output files:
#   data/dependency_graph.csv   — edge list (source of truth)
#   data/graph.rds              — igraph object for index.qmd
#   data/node_attributes.csv    — node metadata for ggraph visualisation
# =============================================================================

suppressPackageStartupMessages({
  library(igraph)
  library(tidygraph)
  library(tidyverse)
})

DATA_DIR <- "data"
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n", strrep("=", 65), "\n", sep = "")
cat("BUILD_GRAPH.R\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M UTC"), "\n")
cat(strrep("=", 65), "\n\n", sep = "")


# =============================================================================
# STEP 1: Write dependency_graph.csv
# -----------------------------------------------------------------------------
# The edge list encodes the firm's complete ICT dependency structure.
# Each row is a directed edge: from_node -> to_node.
#
# Firm profile: €35B AUM, UCITS/AIF, EU-domiciled asset manager.
# 8 vendor relationships, collapsing to 5 independent failure domains.
# (EUROCLEAR and SWIFT are structurally separate; correlated via copula
#  in the simulation frequency layer — see INSTRUCTIONS.md §9.3 and §10.1)
#
# Node naming convention:
#   "FIRM"             — the asset manager (root node)
#   "AWS", "AZURE"...  — CTPP nodes (terminal nodes, uppercase)
#   "Bloomberg",       — non-CTPP vendor nodes (mixed case)
#     "Equinix FR2"
#   "TradeSaaS",       — internal vendor aliases (firm's direct contracts)
#     "RegReportSaaS"
#
# edge_type:
#   "direct"         — firm has a direct contractual relationship with the node
#   "sub_outsourced" — a direct vendor's underlying dependency (DORA RTS 2025/532
#                      sub-outsourcing chain visibility requirement)
#
# criticality:
#   "CIF"     — Critical or Important Function (DORA Article 3(22))
#   "non_CIF" — all other functions
#
# sub_outsourcing_tier:
#   1 = firm -> vendor (direct)
#   2 = vendor -> their vendor (one hop)
#   3 = vendor's vendor -> their vendor (two hops)
#
# ctpp_designated: TRUE if the node is one of the 19 ESA-designated CTPPs
#                  (Nov 2025 JOC list)
# =============================================================================

cat("--- STEP 1: Writing dependency_graph.csv ---\n")

edges <- tribble(
  ~from_node,       ~to_node,        ~edge_type,       ~criticality,
  ~sub_outsourcing_tier, ~service_category,     ~ctpp_designated, ~notes,

  # ---- Cloud infrastructure: AWS (direct) ----
  # The firm hosts its portfolio management system and data lake on AWS EU.
  "FIRM",           "AWS",           "direct",         "CIF",
  1L,                "cloud_infrastructure",  TRUE,
  "Primary cloud — portfolio management system and analytics data lake on AWS eu-central-1",

  # ---- Cloud infrastructure: Azure (direct) ----
  # The firm's Microsoft 365 environment and Azure AD (Entra ID) are CIF
  # because identity services are required for all internal system access.
  "FIRM",           "AZURE",         "direct",         "CIF",
  1L,                "cloud_infrastructure",  TRUE,
  "Microsoft 365 / Entra ID identity layer — required for all internal system access",

  # ---- Order management: TradeSaaS (direct) ----
  # A third-party EMS/OMS SaaS vendor under direct contract with the firm.
  # CIF: trade execution is a core investment function.
  "FIRM",           "TradeSaaS",     "direct",         "CIF",
  1L,                "order_management",      FALSE,
  "Third-party EMS/OMS SaaS — direct contract; vendor's infrastructure runs on AWS",

  # ---- Order management: TradeSaaS -> AWS (sub-outsourced) ----
  # TradeSaaS runs entirely on AWS eu-west-1. This edge exposes the hidden
  # dependency: an AWS outage affects BOTH the firm's direct AWS workloads
  # AND its TradeSaaS platform simultaneously.
  "TradeSaaS",      "AWS",           "sub_outsourced", "CIF",
  2L,                "order_management",      TRUE,
  "TradeSaaS infrastructure hosted on AWS eu-west-1 — confirmed in vendor's TPRA response",

  # ---- Market data: Bloomberg (direct, non-designated) ----
  # Bloomberg was not designated as a CTPP in the Nov 2025 JOC list.
  # Included in the graph as a non-designated critical dependency —
  # a substantive finding about the Register of Information's coverage.
  "FIRM",           "Bloomberg",     "direct",         "CIF",
  1L,                "market_data",           FALSE,
  "Bloomberg Terminal and B-PIPE data feed — non-designated; included for completeness",

  # ---- Settlement / custody: direct Euroclear membership ----
  "FIRM",           "EUROCLEAR",     "direct",         "CIF",
  1L,                "settlement_custody",    TRUE,
  "Direct Euroclear Bank participant for UCITS fund settlement; euro securities",

  # ---- Regulatory reporting: RegReportSaaS (direct) ----
  # A SaaS platform for EMIR, AIFMD Annex IV, and MiFID II transaction reporting.
  # Non-CIF: regulatory reporting does not directly affect investment operations
  # in real time, but DORA Article 19 incident thresholds apply.
  "FIRM",           "RegReportSaaS", "direct",         "non_CIF",
  1L,                "regulatory_reporting",  FALSE,
  "SaaS regulatory reporting platform (EMIR / AIFMD / MiFID II) — runs on Azure",

  # ---- Regulatory reporting: RegReportSaaS -> Azure (sub-outsourced) ----
  # The reporting platform runs on Azure West Europe. This creates the second
  # hidden dependency: an Azure outage impairs both the firm's direct Azure
  # workloads and its regulatory reporting capability.
  "RegReportSaaS",  "AZURE",         "sub_outsourced", "non_CIF",
  2L,                "regulatory_reporting",  TRUE,
  "RegReportSaaS hosted on Azure West Europe — confirmed in vendor SOC 2 report",

  # ---- Network connectivity: Equinix FR2 co-location (direct) ----
  # The firm co-locates its network equipment at Equinix FR2 for direct
  # market connectivity (Xetra, Euronext, Deutsche Börse).
  "FIRM",           "EQUINIX",       "direct",         "CIF",
  1L,                "network_connectivity",  TRUE,
  "Co-location at Equinix FR2 Frankfurt for direct market connectivity",

  # ---- Interbank messaging: SWIFT (direct) ----
  # The firm is a SWIFT direct participant for fund transfer instructions
  # and custodian communications. CIF: required for settlement instructions.
  "FIRM",           "SWIFT",         "direct",         "CIF",
  1L,                "settlement_custody",    TRUE,
  "SWIFT direct participant — fund transfer instructions and custodian SWIFT messages"
)

# Write to CSV
dep_graph_path <- file.path(DATA_DIR, "dependency_graph.csv")
write_csv(edges, dep_graph_path)
cat(sprintf("  [OK]  Written: %s (%d edges)\n", dep_graph_path, nrow(edges)))


# =============================================================================
# STEP 2: Construct igraph object
# -----------------------------------------------------------------------------
# Directed graph: edges point FROM the dependent node TO the dependency.
# e.g. FIRM -> AWS means "FIRM depends on AWS"
# e.g. TradeSaaS -> AWS means "TradeSaaS depends on AWS"
#
# This direction means: to find all services impacted by an AWS outage,
# traverse the REVERSED graph from the AWS node upward to FIRM.
# igraph::subcomponent(graph_rev, "AWS", mode = "out") returns all nodes
# that reach AWS in the forward graph — i.e. all nodes that depend on AWS.
# =============================================================================

cat("\n--- STEP 2: Constructing igraph object ---\n")

# Build vertex attribute table — one row per unique node
all_nodes <- unique(c(edges$from_node, edges$to_node))

node_attrs <- tibble(name = all_nodes) |>
  mutate(
    node_type = case_when(
      name == "FIRM"                         ~ "firm",
      name %in% c("TradeSaaS",
                   "RegReportSaaS",
                   "Bloomberg")              ~ "vendor",
      TRUE                                   ~ "ctpp"
    ),
    ctpp_designated = case_when(
      name %in% c("AWS","AZURE","GCP",
                   "EQUINIX","SWIFT",
                   "EUROCLEAR","CLEARSTREAM",
                   "SAP","SALESFORCE")        ~ TRUE,
      TRUE                                    ~ FALSE
    ),
    service_category = case_when(
      name %in% c("AWS","AZURE")              ~ "cloud_infrastructure",
      name == "TradeSaaS"                     ~ "order_management",
      name == "Bloomberg"                     ~ "market_data",
      name == "EUROCLEAR"                     ~ "settlement_custody",
      name == "RegReportSaaS"                 ~ "regulatory_reporting",
      name == "EQUINIX"                       ~ "network_connectivity",
      name == "SWIFT"                         ~ "settlement_custody",
      name == "FIRM"                          ~ "root",
      TRUE                                    ~ "other"
    ),
    # CIF status: a node is CIF if ANY edge to/from it is CIF
    # Computed after graph construction; initialised here as NA
    any_cif = NA
  )

# Resolve CIF status from edge list
cif_nodes <- edges |>
  filter(criticality == "CIF") |>
  select(from_node, to_node) |>
  pivot_longer(everything(), names_to = NULL, values_to = "name") |>
  pull(name) |>
  unique()

node_attrs <- node_attrs |>
  mutate(any_cif = name %in% cif_nodes)

# Construct graph
g <- graph_from_data_frame(
  d        = edges |> select(from = from_node, to = to_node,
                              edge_type, criticality,
                              sub_outsourcing_tier, service_category,
                              ctpp_designated),
  directed = TRUE,
  vertices = node_attrs
)

cat(sprintf("  [OK]  Graph: %d nodes | %d edges | directed: %s\n",
            vcount(g), ecount(g), is_directed(g)))


# =============================================================================
# STEP 3: Graph structure validation
# -----------------------------------------------------------------------------
# Checks:
#   3a. All nodes present
#   3b. FIRM is the root (in-degree 0 from other nodes' perspective — but
#       since edges point from dependent to dependency, FIRM has out-degree > 0
#       and in-degree 0 in the forward graph, or vice versa — confirm)
#   3c. All CTPP nodes are terminal (no out-edges in forward graph, because
#       CTPPs are the end of the dependency chain in our model)
#   3d. No cycles (DAG property — required for subcomponent() correctness)
#   3e. No isolated nodes
#   3f. Each service category has at least one CIF edge
# =============================================================================

cat("\n--- STEP 3: Graph structure validation ---\n")

graph_issues <- character(0)

# 3a. Expected nodes present
expected_nodes <- c("FIRM","AWS","AZURE","TradeSaaS","Bloomberg",
                    "EUROCLEAR","RegReportSaaS","EQUINIX","SWIFT")
missing_nodes  <- setdiff(expected_nodes, V(g)$name)
if (length(missing_nodes) > 0) {
  graph_issues <- c(graph_issues,
                    sprintf("Missing nodes: %s", paste(missing_nodes, collapse=", ")))
} else {
  cat(sprintf("  [PASS] All %d expected nodes present\n", length(expected_nodes)))
}

# 3b. FIRM has out-edges only (it is the root dependent, not depended upon)
firm_in <- length(incident(g, "FIRM", mode = "in"))
if (firm_in > 0) {
  graph_issues <- c(graph_issues,
    sprintf("FIRM has %d in-edges — should have none (FIRM is root)", firm_in))
} else {
  cat(sprintf("  [PASS] FIRM is root node (0 in-edges, %d out-edges)\n",
              length(incident(g, "FIRM", mode = "out"))))
}

# 3c. CTPP nodes are terminal (no out-edges — they are the end of the chain)
ctpp_nodes <- c("AWS","AZURE","EUROCLEAR","EQUINIX","SWIFT")
for (ctpp in ctpp_nodes) {
  if (!ctpp %in% V(g)$name) next
  out_deg <- length(incident(g, ctpp, mode = "out"))
  if (out_deg > 0) {
    graph_issues <- c(graph_issues,
      sprintf("%s has %d out-edges — CTPP nodes should be terminal", ctpp, out_deg))
  }
}
if (length(graph_issues) == 0) {
  cat(sprintf("  [PASS] All %d CTPP nodes are terminal (0 out-edges)\n",
              length(ctpp_nodes)))
}

# 3d. DAG property — no cycles
if (is_dag(g)) {
  cat("  [PASS] Graph is a DAG (no cycles)\n")
} else {
  graph_issues <- c(graph_issues, "Graph contains cycles — not a DAG")
}

# 3e. No isolated nodes
isolated <- V(g)$name[degree(g) == 0]
if (length(isolated) > 0) {
  graph_issues <- c(graph_issues,
    sprintf("Isolated nodes (no edges): %s", paste(isolated, collapse=", ")))
} else {
  cat("  [PASS] No isolated nodes\n")
}

# 3f. CIF service categories covered
cif_cats <- edges |> filter(criticality == "CIF") |> pull(service_category) |> unique()
expected_cif_cats <- c("cloud_infrastructure","order_management",
                        "settlement_custody","network_connectivity")
missing_cif_cats  <- setdiff(expected_cif_cats, cif_cats)
if (length(missing_cif_cats) > 0) {
  graph_issues <- c(graph_issues,
    sprintf("CIF coverage gap: %s", paste(missing_cif_cats, collapse=", ")))
} else {
  cat(sprintf("  [PASS] CIF coverage: %s\n", paste(cif_cats, collapse=", ")))
}

# Report validation result
if (length(graph_issues) > 0) {
  cat("\n  [FAIL] Graph structure issues:\n")
  for (issue in graph_issues) cat(sprintf("    -> %s\n", issue))
  cat("\n  Resolve issues above before proceeding to index.qmd\n\n")
  stop("Graph validation failed — see issues above")
} else {
  cat("  [PASS] All graph structure checks passed\n")
}


# =============================================================================
# STEP 4: Failure domain analysis
# -----------------------------------------------------------------------------
# The headline finding of the project:
# How many independent failure domains does the firm's 8-vendor ICT footprint
# actually represent?
#
# Method: reverse the graph, then for each CTPP node compute
# subcomponent(g_rev, ctpp, mode="out") — the set of nodes that would be
# impacted by an outage at that CTPP.
#
# A failure domain is a set of firm-level services (nodes directly connected
# to FIRM) that share at least one common CTPP dependency. CTPPs that produce
# identical or overlapping impact sets belong to the same failure domain.
# =============================================================================

cat("\n--- STEP 4: Failure domain analysis ---\n")

g_rev <- reverse_edges(g)

# Firm-level services = nodes with a direct edge FROM FIRM
firm_services <- edges |>
  filter(from_node == "FIRM") |>
  pull(to_node)

cat(sprintf("  Firm-level services (direct vendor relationships): %d\n",
            length(firm_services)))
cat(sprintf("  Services: %s\n\n", paste(firm_services, collapse=", ")))

# For each CTPP, find all firm services in its impact set
ctpp_impact <- map(ctpp_nodes, function(ctpp) {
  if (!ctpp %in% V(g_rev)$name) return(character(0))
  # subcomponent on reversed graph from CTPP: returns all nodes that
  # depend on this CTPP (directly or through sub-outsourcing)
  impacted <- subcomponent(g_rev, ctpp, mode = "out")$name
  # Intersect with firm-level services to get the services at risk
  intersect(impacted, firm_services)
}) |> set_names(ctpp_nodes)

cat("  Impact set per CTPP (firm services impaired by an outage):\n")
for (ctpp in ctpp_nodes) {
  services <- ctpp_impact[[ctpp]]
  cat(sprintf("    %-12s -> %s\n",
              ctpp,
              if (length(services) == 0) "(none in scope)"
              else paste(services, collapse=", ")))
}

# Identify failure domains: group CTPPs by identical impact set
impact_signatures <- map_chr(ctpp_nodes, function(ctpp) {
  paste(sort(ctpp_impact[[ctpp]]), collapse="|")
}) |> set_names(ctpp_nodes)

domain_groups <- split(ctpp_nodes, impact_signatures)
# Remove empty-impact groups
domain_groups <- domain_groups[map_lgl(domain_groups,
                                        ~ length(ctpp_impact[[.x[1]]]) > 0)]

n_domains <- length(domain_groups)

cat(sprintf("\n  Failure domains: %d (from %d CTPP nodes)\n",
            n_domains, length(ctpp_nodes)))
cat("  Domain structure:\n")

domain_df <- map_dfr(seq_along(domain_groups), function(d) {
  ctpps    <- domain_groups[[d]]
  services <- ctpp_impact[[ctpps[1]]]
  cif_flag <- any(edges |>
                    filter(from_node %in% c("FIRM", firm_services),
                           to_node %in% ctpps,
                           criticality == "CIF") |>
                    nrow() > 0)
  cat(sprintf("    Domain %d: CTPPs [%s] -> Services [%s] | CIF: %s\n",
              d,
              paste(ctpps, collapse=", "),
              paste(services, collapse=", "),
              if (cif_flag) "YES" else "no"))
  tibble(
    domain_id        = d,
    ctpps            = paste(ctpps, collapse=", "),
    services_at_risk = paste(services, collapse=", "),
    n_ctpps          = length(ctpps),
    n_services       = length(services),
    contains_cif     = cif_flag
  )
})

# The key metric: vendor count vs failure domain count
cat(sprintf("\n  Vendor count:         %d\n", length(firm_services)))
cat(sprintf("  Independent failure domains: %d\n", n_domains))
cat(sprintf("  Concentration ratio:  %.1fx (vendor count / domain count)\n",
            length(firm_services) / n_domains))
cat("\n  This ratio is the quantitative basis for the document's central claim:\n")
cat("  vendor-count concentration metrics understate true tail exposure\n")
cat("  because sub-outsourcing chains collapse multiple vendors to shared\n")
cat("  underlying failure points.\n")


# =============================================================================
# STEP 5: Sub-outsourcing chain visibility diagnostic
# -----------------------------------------------------------------------------
# Identifies which firm-level vendors have sub-outsourcing chains that
# expose hidden CTPP dependencies — the DORA RTS 2025/532 compliance gap
# that the model quantifies.
# =============================================================================

cat("\n--- STEP 5: Sub-outsourcing chain visibility ---\n")

sub_edges <- edges |> filter(edge_type == "sub_outsourced")

if (nrow(sub_edges) == 0) {
  cat("  [INFO] No sub-outsourcing edges in graph — all dependencies are direct\n")
} else {
  cat(sprintf("  Sub-outsourcing edges: %d\n", nrow(sub_edges)))
  cat("  Hidden CTPP dependencies (not visible in Register of Information Tier 1):\n")

  sub_edges |>
    group_by(from_node) |>
    summarise(
      underlying_ctpps = paste(to_node, collapse=", "),
      criticality      = first(criticality),
      .groups          = "drop"
    ) |>
    pmap(function(from_node, underlying_ctpps, criticality, ...) {
      cat(sprintf("    %-16s depends on CTPP(s): %-20s [%s]\n",
                  from_node, underlying_ctpps, criticality))
    })

  cat("\n  Register of Information (Tier 1 view): firm lists these as direct vendors\n")
  cat("  Model (Tier 2 view):                   firm is exposed to their CTPP hosts\n")
  cat("  VaR impact:                            AWS cluster VaR is understated\n")
  cat("                                         if TradeSaaS treated as independent\n")
}


# =============================================================================
# STEP 6: Save outputs
# =============================================================================

cat("\n--- STEP 6: Saving outputs ---\n")

# Save igraph object
graph_path <- file.path(DATA_DIR, "graph.rds")
saveRDS(g, graph_path)
cat(sprintf("  [OK]  Saved: %s\n", graph_path))

# Save node attributes for ggraph visualisation in index.qmd
node_attr_path <- file.path(DATA_DIR, "node_attributes.csv")
node_attrs_out <- tibble(
  name             = V(g)$name,
  node_type        = V(g)$node_type,
  ctpp_designated  = V(g)$ctpp_designated,
  service_category = V(g)$service_category,
  any_cif          = V(g)$any_cif
)
write_csv(node_attrs_out, node_attr_path)
cat(sprintf("  [OK]  Saved: %s (%d nodes)\n", node_attr_path, nrow(node_attrs_out)))

# Save domain summary for use in index.qmd results section
domain_path <- file.path(DATA_DIR, "failure_domains.csv")
write_csv(domain_df, domain_path)
cat(sprintf("  [OK]  Saved: %s (%d domains)\n", domain_path, nrow(domain_df)))

# Save impact set for use in the concentration decomposition chart
impact_path <- file.path(DATA_DIR, "ctpp_impact.csv")
impact_out  <- map_dfr(ctpp_nodes, function(ctpp) {
  tibble(
    ctpp             = ctpp,
    impacted_service = if (length(ctpp_impact[[ctpp]]) > 0)
                         ctpp_impact[[ctpp]] else NA_character_
  )
})
write_csv(impact_out, impact_path)
cat(sprintf("  [OK]  Saved: %s\n", impact_path))


# =============================================================================
# FINAL SUMMARY
# =============================================================================

cat("\n", strrep("=", 65), "\n", sep = "")
cat("BUILD_GRAPH COMPLETE — Summary\n")
cat(strrep("=", 65), "\n\n", sep = "")

cat(sprintf("  Nodes:              %d\n", vcount(g)))
cat(sprintf("  Edges:              %d\n", ecount(g)))
cat(sprintf("  Vendor entries:     %d (Register of Information view)\n",
            length(firm_services)))
cat(sprintf("  Failure domains:    %d (network model view)\n", n_domains))
cat(sprintf("  Concentration ratio: %.1fx\n\n",
            length(firm_services) / n_domains))

cat("  Output files:\n")
for (f in c(dep_graph_path, graph_path, node_attr_path,
            domain_path, impact_path)) {
  if (file.exists(f)) {
    cat(sprintf("    [OK]  %s\n", f))
  } else {
    cat(sprintf("    [MISSING] %s\n", f))
  }
}

cat("\nNext steps:\n")
cat("  1. Populate data/parameters.csv using lambda estimates from\n")
cat("     validate_incidents.R output (lambda summary table)\n")
cat("  2. Verify data/dependency_graph.csv firm profile matches\n")
cat("     INSTRUCTIONS.md Section 9.3\n")
cat("  3. Begin index.qmd\n\n")
