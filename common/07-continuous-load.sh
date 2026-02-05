#!/bin/bash
echo "Lancement de la charge continue sur $(hostname)..."
echo "Appuyez sur [CTRL+C] pour arrêter."

# Boucle infinie
while true; do
  # Lancer 5 invocations en parallèle pour augmenter la charge CPU/RAM
  for i in {1..5}; do
    wsk action invoke hello-kata --blocking > /dev/null 2>&1 &
  done
  
  # Attendre que les 5 finissent (ou un court instant)
  wait
  echo -ne "Invocations en cours... $(date +%T) \r"
done