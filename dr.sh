#!/bin/bash

# reinstall kasten 
echo "Reinstalling Kasten"
helm  install k10 kasten/k10 --namespace=kasten-io -f k10-values.yaml --create-namespace --wait
echo "Kasten successfully reinstalled"

# recreate the backup location and the pass phrase used by the disaster recovery job
echo "Recreating the backup location and the pass phrase"
kubectl create -f dr.yaml
echo "Backup location and pass phrase successfully recreated"

echo "create the token secret to access kasten" 
cat <<EOF |kubectl create -n kasten-io -f -
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: k10-k10-token
  annotations:
    kubernetes.io/service-account.name: k10-k10
EOF

# grab the uidcluster in the previouscluster configmap
echo "Grabbing the uidcluster in the previouscluster configmap"
uid=$(kubectl get configmap -n kasten-io previous-cluster -o jsonpath='{.data.uidcluster}')
profileName=$(kubectl get profiles.config.kio.kasten.io -n kasten-io -o jsonpath='{.items[0].metadata.name}')


# execute the disaster recovery with the helm chart
echo "Restoring the calalog of the previous cluster"
helm install k10-restore kasten/k10restore --namespace=kasten-io \
    --set sourceClusterID=$uid \
    --set profile.name=$profileName \
    --wait
echo "restoration of the catalog started"

echo "waiting for the kasten dr to complete" 
kubectl -n kasten-io wait --for='jsonpath={.status.succeeded}=1' job/k10-restore-k10restore
echo "kasten dr completed" 

# make sure crypto pod is running (it's the last pod to be restarted after dr)
sleep 10
echo "waiting for crypto pod to be ready" 
kubectl -n kasten-io wait --for=condition=Ready pod -l component=crypto --timeout=120s

echo "restoring all the apps with a batch restore action"
cat<<EOF |kubectl create -f -
apiVersion: actions.kio.kasten.io/v1alpha1
kind: BatchRestoreAction
metadata:
  generateName: batchrestore-
  namespace: kasten-io
spec:
  subjects:
    - namespace: mysql
    - namespace: pacman
    - namespace: postgres
    - namespace: elastic
EOF




