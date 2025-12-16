#!/bin/bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-gamemetrics}
DB_SERVICE_PUBLIC=${DB_SERVICE_PUBLIC:-timescaledb-public}
DB_SERVICE_INTERNAL=${DB_SERVICE_INTERNAL:-timescaledb.gamemetrics.svc.cluster.local}
DB_USER=${DB_USER:-postgres}
DB_NAME=${DB_NAME:-gamemetrics}

# Pick host: prefer public LB if it has an external hostname; otherwise use internal ClusterIP DNS.
HOST=$(kubectl get svc "${DB_SERVICE_PUBLIC}" -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -z "$HOST" ]; then
  HOST=${DB_SERVICE_INTERNAL}
fi

echo "Using DB host: $HOST"

DB_PASSWORD=$(kubectl get secret db-credentials -n "${NAMESPACE}" -o go-template='{{.data.password | base64decode}}')

# psql smoke test from an ephemeral pod
kubectl run psql-smoke-$$ -n "${NAMESPACE}" --rm -i --restart=Never --image=postgres:15 --env "PGPASSWORD=${DB_PASSWORD}" --command -- \
  psql -h "$HOST" -U "$DB_USER" -d "$DB_NAME" -c 'select 1;' && echo "DB connectivity OK" || { echo "DB connectivity FAILED"; exit 1; }
