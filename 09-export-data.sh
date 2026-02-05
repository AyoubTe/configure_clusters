#!/bin/bash
# Script d'exportation des données énergétiques (Prometheus -> CSV)
# Récupère la consommation (Watts) du namespace 'openwhisk' sur les 15 dernières minutes

OUTPUT_FILE="energy_data_$(hostname).csv"
PROMETHEUS_PORT=9090

echo "📊 Préparation de l'export pour $(hostname)..."

# 1. Ouvrir le tunnel vers Prometheus en arrière-plan
echo "   -> Ouverture du port-forwarding..."
kubectl port-forward -n monitoring svc/monitoring-stack-kube-prom-prometheus $PROMETHEUS_PORT:$PROMETHEUS_PORT > /dev/null 2>&1 &
PF_PID=$!
sleep 3 # Attendre que la connexion soit établie

# 2. Script Python embarqué pour requêter l'API et formater en CSV
# On utilise 'rate' sur 1m pour lisser et obtenir des Watts (Joules/seconde)
cat <<EOF > exporter.py
import urllib.request
import json
import time
import csv

# Configuration
end_time = time.time()
start_time = end_time - (15 * 60) # 15 dernières minutes
step = "5s" # Un point toutes les 5 secondes
query = 'sum(rate(kepler_container_joules_total{container_namespace="openwhisk"}[1m]))'

url = f"http://localhost:9090/api/v1/query_range?query={query}&start={start_time}&end={end_time}&step={step}"

try:
    with urllib.request.urlopen(url) as response:
        data = json.load(response)
        
    results = data['data']['result']
    
    with open("$OUTPUT_FILE", 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['Timestamp', 'Datetime', 'Watts'])
        
        if results:
            values = results[0]['values']
            for v in values:
                ts = float(v[0])
                watts = float(v[1])
                dt = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(ts))
                writer.writerow([ts, dt, watts])
            print(f"   -> Succès ! {len(values)} points de mesure exportés.")
        else:
            print("   -> Avertissement : Aucune donnée trouvée pour le namespace 'openwhisk'.")

except Exception as e:
    print(f"   -> Erreur : {e}")
EOF

# 3. Exécuter l'export
echo "   -> Interrogation de Prometheus..."
python3 exporter.py

# 4. Nettoyage
kill $PF_PID
rm exporter.py

echo ""
echo "Export terminé : $OUTPUT_FILE"
echo "Copiez le contenu ci-dessous pour le coller dans Excel :"
echo "---------------------------------------------------------"
cat $OUTPUT_FILE
echo "---------------------------------------------------------"