#!/bin/bash
# Script de Stress Test - Génération de charge OpenWhisk
# Lance 100 invocations séquentielles pour visualiser la conso sur Grafana

echo "Démarrage du Stress Test sur $(hostname)..."
echo "Target: Action 'hello-kata'"

START_TIME=$(date +%s%3N)

for i in {1..100}; do
  # Invoque l'action (le paramètre --blocking force l'attente du résultat)
  wsk action invoke hello-kata --blocking > /dev/null 2>&1
  
  # Barre de progression simple
  echo -ne "Invocation $i/100... \r"
done

END_TIME=$(date +%s%3N)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "Test terminé en ${DURATION} ms"