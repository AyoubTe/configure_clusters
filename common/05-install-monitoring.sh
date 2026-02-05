#!/bin/bash
#####################################################################
# Script Complet de Monitoring (Kepler + Prometheus + Grafana)
# Purpose: Installe toute la chaîne de mesure énergétique en une fois
#####################################################################

set -e

# Codes couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

#####################################################################
# 1. Configuration des Repos Helm
#####################################################################
log_info "Configuration des repositories Helm..."
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
log_info "✓ Repos à jour"

#####################################################################
# 2. Installation de Kepler (Sondes Énergétiques eBPF)
#####################################################################
log_info "Installation de Kepler (Sondes)..."

# Création namespace si inexistant
kubectl create namespace kepler --dry-run=client -o yaml | kubectl apply -f -

# Installation avec les paramètres optimisés pour vos VMs (Estimateur activé)
helm upgrade --install kepler kepler/kepler \
    --namespace kepler \
    --set serviceMonitor.enabled=true \              # CHANGED to true
    --set serviceMonitor.labels.release=monitoring-stack \ # ADDED so Prometheus finds it
    --set prometheus.enabled=true \
    --set estimator.enabled=true \
    --set model.server.enabled=false \
    --wait

log_info "✓ Kepler est installé et tourne sur les noeuds"

#####################################################################
# 3. Installation de la Stack Monitoring (Prometheus + Grafana)
#####################################################################
log_info "Installation de Prometheus et Grafana..."

# Création namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Installation de la stack (Version allégée pour économiser le CPU)
helm upgrade --install monitoring-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set alertmanager.enabled=false \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=31000 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --wait

log_info "✓ Stack Monitoring installée"

#####################################################################
# 4. Patch de Connexion (Prometheus -> Kepler)
#####################################################################
log_info "Configuration des droits d'accès Prometheus vers Kepler..."

# Donne à Prometheus le droit de lire les métriques dans tous les namespaces (y compris 'kepler')
kubectl create clusterrolebinding prometheus-view-kepler \
  --clusterrole=view \
  --serviceaccount=monitoring:monitoring-stack-kube-prom-prometheus \
  --dry-run=client -o yaml | kubectl apply -f -

# On s'assure que Kepler exporte bien ses métriques pour Prometheus
# (Cette étape est souvent automatique, mais on force la découverte si besoin)
kubectl label namespace kepler monitoring=true --overwrite || true

#####################################################################
# 5. Récapitulatif d'accès
#####################################################################
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   SYSTÈME DE MESURE ÉNERGÉTIQUE OPÉRATIONNEL${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "1. Accédez à Grafana ici : http://$NODE_IP:31000"
echo "2. Login par défaut      : admin"
echo "3. Mot de passe          : "

kubectl get secret --namespace monitoring monitoring-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

echo ""
echo -e "${YELLOW}IMPORTANT POUR VOTRE RAPPORT :${NC}"
echo "Pour visualiser la consommation, importez le dashboard officiel Kepler :"
echo "   -> Menu Dashboards > Import > ID: 19161"
echo ""