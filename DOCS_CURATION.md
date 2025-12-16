# Documentation Curation

Use this as the single index of what to keep vs. what is deprecated. The goal is to keep a small, authoritative doc set and clearly mark everything else as deprecated.

## Canonical (keep)
- `README.md` — top-level overview and quick start.
- `ARCHITECTURE_OVERVIEW.md` — detailed architecture (ASCII + flows).
- `PRODUCTION_READINESS_CHECKLIST.md` — what’s needed for production.
- `COMPLETE_FINAL_REVIEW.md` — final status and gaps.
- `REQUIREMENTS_VS_IMPLEMENTATION.md` — requirement mapping.
- `MISSING_COMPONENTS_SUMMARY.md` — remaining gaps.
- `QUICK_START_INSTANT_SYNC.md` — instant ArgoCD sync how-to.
- `ARGOCD_WORKFLOW_EXPLAINED.md` — GitOps flow explained.
- `scripts/README.md` and `scripts/SCRIPTS_SUMMARY.md` — how to use scripts.

## Important operational references
- Runbooks in `docs/runbooks/` (DR, scaling, deployment, troubleshooting).
- Keep `DEMO.sh` only if you demo end-to-end.

## Deprecated (keep for now, but do not rely on)
- Older/duplicate guides: `PRODUCTION_GUIDE.txt`, `PRODUCTION_READY_SUMMARY.txt`, `NEXT_STEPS.md`, `PROJECT_ROADMAP.md`, `CURRENT_STATUS.md`, `DEPLOYMENT_GUIDE.md`, `PHASE3_COMPLETE.md`, `OBSERVABILITY_GUIDE.md`, `ARGOCD_GITOPS_GUIDE.txt`, `SIMPLE_ARGOCD_EXPLANATION.md`, `CI_CD_TESTING_GUIDE.txt`, `CI_CD_TEST_REPORT.md`, `WORKFLOW_TRIGGERS.md`, `WORKFLOW_SBOM_FIX.md`, `EVENT_INGESTION_CI_FIX.md`, `APPLICATION_SETUP.md`, `SESSION_NOTES.md`, `README.sh`, `KUSTOMIZATION_FLOW.md`, `KUSTOMIZATION_QUICK_REFERENCE.md`.
- Any other `.txt`/`.md` not listed in Canonical that overlap in content.

## Scripts already deprecated
- `deploy-complete.sh`, `deploy-infra-only.sh`, `deploy-apps-to-k8s.sh`, `update-deployment-image.sh`, `update-secrets.sh`, `teardown-infrastructure.sh`.

## Suggested next step
- Move deprecated docs/scripts to an `archive/` folder (or delete) before pushing. This file is the source of truth for what stays primary.

