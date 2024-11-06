aws eks --region us-east-1 update-kubeconfig --name drupal

aws eks create-nodegroup --cluster-name drupal --nodegroup-name kokc_drupal --node-role arn:aws:iam::820176242712:role/LabRole --subnets subnet-0f210fe533155c168 subnet-0d0b759bb85986f2d subnet-0372e2d7ec6085b09 --scaling-config minSize=1,maxSize=3,desiredSize=2 --instance-types t3.medium --ami-type AL2_x86_64

kubectl get all

===========================================================================

kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/ecr/?ref=release-1.3"


curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version


helm repo add stable https://charts.helm.sh/stable
helm repo update


helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

===========================================================================

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

kubectl get pods -n ingress-nginx

===========================================================================

nano drupal-pv.yaml

########################
apiVersion: v1
kind: PersistentVolume
metadata:
  name: drupal-pv
spec:
  capacity:
    storage: 5Gi 
  accessModes:
    - ReadWriteMany  
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: efs.csi.aws.com
    volumeHandle: fs-02f6f4578210e2c0b
########################

kubectl apply -f drupal-pv.yaml

===========================================================================

nano drupal-pvc.yaml

########################
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: drupal-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
########################

kubectl apply -f drupal-pvc.yaml

===========================================================================

nano db-pv.yaml

########################
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data
########################

kubectl apply -f db-pv.yaml

===========================================================================

nano db-pvc.yaml

########################
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
########################

kubectl apply -f db-pvc.yaml

kubectl get pvc

===========================================================================

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.8.0/cert-manager.yaml

nano cluster-issuer.yaml

########################
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: maiguec999@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
########################

kubectl apply -f cluster-issuer.yaml

===========================================================================

nano drupal-certificate.yaml

########################
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: drupal-tls
  namespace: default 
spec:
  secretName: tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: reto2.kokcengine.site
  dnsNames:
    - reto2.kokcengine.site
########################

kubectl apply -f drupal-certificate.yaml

===========================================================================

nano deploy.yaml

########################
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drupal
spec:
  replicas: 1
  selector:
    matchLabels:
      app: drupal
  template:
    metadata:
      labels:
        app: drupal
    spec:
      containers:
        - name: drupal
          image: bitnami/drupal:latest
          ports:
            - containerPort: 8080
          env:
            - name: BITNAMI_DEBUG
              value: "true"
            - name: DRUPAL_DATA_TO_PERSIST
              value: "sites themes modules profiles"
            - name: DRUPAL_SKIP_BOOTSTRAP
              value: "yes"
            - name: DRUPAL_HASH_SALT
              value: "89f19dbfe6df8d936305a84c0ef632e605dbcd35497a62bf03e6d7faca3ae3f0"
            - name: DRUPAL_CONFIG_SYNC_DIR
              value: "/var/www/html/sites/default/files/config"
            - name: DRUPAL_DATABASE_HOST
              value: 'db-service'
            - name: DRUPAL_DATABASE_NAME
              value: "drupal"
            - name: DRUPAL_DATABASE_USER
              value: "drupaluser"
            - name: DRUPAL_DATABASE_PASSWORD
              value: "drupalpassword"
          volumeMounts:
            - name: drupal-files
              mountPath: /var/www/html/modules
              subPath: modules
            - name: drupal-files
              mountPath: /var/www/html/profiles
              subPath: profiles
            - name: drupal-files
              mountPath: /var/www/html/sites
              subPath: sites
            - name: drupal-files
              mountPath: /var/www/html/themes
              subPath: themes
            - name: drupal-files
              mountPath: /var/www/html/sites/default/files/config
              subPath: config
      volumes:
        - name: drupal-files
          persistentVolumeClaim:
            claimName: drupal-pvc
########################

kubectl apply -f deploy.yaml

===========================================================================

nano ingress.yaml

########################
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: drupal-ingress
  namespace: default  
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx 
  rules:
    - host: reto2.kokcengine.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: drupal-service
                port:
                  number: 80
  tls:
    - hosts:
        - reto2.kokcengine.site
      secretName: tls-secret  
########################

kubectl apply -f ingress.yaml

===========================================================================

nano deploy-db.yaml

########################
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drupal-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: drupal-db
  template:
    metadata:
      labels:
        app: drupal-db
    spec:
      containers:
        - name: mariadb
          image: bitnami/mariadb:latest
          env:
            - name: MARIADB_ROOT_PASSWORD
              value: "your_root_password"
            - name: MARIADB_DATABASE
              value: "drupal"
            - name: MARIADB_USER
              value: "drupaluser"
            - name: MARIADB_PASSWORD
              value: "drupalpassword"
          ports:
            - containerPort: 3306
      volumes:
        - name: mariadb-storage
          persistentVolumeClaim:
            claimName: mariadb-pvc
########################

kubectl apply -f deploy-db.yaml

===========================================================================

nano service.yaml

########################
apiVersion: v1
kind: Service
metadata:
  name: drupal-service
spec:
  type: ClusterIP
  selector:
    app: drupal
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
########################

kubectl apply -f service.yaml

===========================================================================

nano service-db.yaml

########################
apiVersion: v1
kind: Service
metadata:
  name: db-service
spec:
  selector:
    app: drupal-db
  ports:
    - protocol: TCP
      port: 3306
      targetPort: 3306
########################

kubectl apply -f service-db.yaml

===========================================================================

kubectl describe pod

kubectl delete pod

kubectl scale deployment drupal --replicas=1
