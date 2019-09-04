kubectl apply -f - <<EOF
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: prometheus-claim
  namespace: mon
  annotations:
    volume.beta.kubernetes.io/storage-class: "fst-${REGION}-${ZONE_POSFIX_1}-${ZONE_POSFIX_2}"
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: ${PROM_PV_SIZE}
  selector:
    matchLabels:
      pv-type: "prom-fst-pv"
EOF
