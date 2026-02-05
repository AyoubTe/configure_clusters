#!/bin/bash
# 08-final-experiment.sh
# Lance 500 invocations (mélange de blocking et non-blocking) pour saturer le CPU

echo "Démarrage de l'expérience scientifique sur $(hostname)..."
echo "Target: namespace 'openwhisk'"

# Marqueur de temps pour votre rapport
echo "Début : $(date +%H:%M:%S)"

# Phase 1 : Charge progressive (Warm up)
for i in {1..50}; do
  wsk action invoke hello-kata --blocking > /dev/null 2>&1
  echo -ne "Warm-up $i/50... \r"
done

echo -e "\nPhase 2 : Charge Intense (Parallèle)..."
# Phase 2 : Tir de barrage (Burst)
for i in {1..200}; do
  # On lance en tâche de fond (&) pour créer un pic de consommation
  wsk action invoke hello-kata > /dev/null 2>&1 &
  
  # On limite un peu le parallélisme pour ne pas crasher l'invoker (batch de 10)
  if (( $i % 10 == 0 )); then wait; fi
  echo -ne "Burst $i/200... \r"
done

wait
echo -e "\nExpérience terminée à $(date +%H:%M:%S)"