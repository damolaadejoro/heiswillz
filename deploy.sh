#!/bin/bash

NAMESPACE="devops-exercise"

if [ "$1" == "install" ]; then
    echo "Installing DevOps Exercise..."

    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

    # Deploy PostgreSQL
    kubectl apply -f postgres-secret.yaml
    kubectl apply -f grafana-secret.yaml
    helm install postgres bitnami/postgresql -n $NAMESPACE -f values-postgres.yaml

    # Deploy Traefik
    helm install traefik traefik/traefik -n $NAMESPACE -f values-traefik.yaml

    # Deploy Jenkins
    helm install jenkins jenkins/jenkins -n $NAMESPACE -f values-jenkins.yaml

    # Deploy Grafana
    helm install grafana grafana/grafana -n $NAMESPACE -f values-grafana.yaml

    # Apply Ingress Resources
    kubectl apply -f ingress-resources.yaml

    # Wait for services to be ready
    echo "Waiting for services to be ready..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n $NAMESPACE --timeout=300s
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=jenkins -n $NAMESPACE --timeout=300s

    # Deploy Prometheus and PostgreSQL Exporter
    helm install prometheus prometheus-community/kube-prometheus-stack -n $NAMESPACE \
      --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
    helm install postgres-exporter prometheus-community/prometheus-postgres-exporter -n $NAMESPACE \
      --set config.datasource.host=postgres-postgresql \
      --set config.datasource.user=postgres \
      --set config.datasource.password=postgres \
      --set config.datasource.database=appdb

    # Apply Terraform for Grafana dashboard
    if [ ! -d "terraform" ]; then
        echo "Error: 'terraform' directory not found."
        exit 1
    fi
    cd terraform
    terraform init
    terraform apply -auto-approve
    cd ..

    # Output important information
    MINIKUBE_IP=$(minikube ip)
    echo "Installation complete. Please ensure you've added these entries to your /etc/hosts file:"
    echo "$MINIKUBE_IP jenkins.local"
    echo "$MINIKUBE_IP grafana.local"
    echo "$MINIKUBE_IP traefik.local"
    
    # Get Traefik LoadBalancer IP/Port
    echo "Traefik service details:"
    kubectl get svc traefik -n $NAMESPACE -o wide
    
    echo "Configure Jenkins Job DSL at http://jenkins.local and run SeedJob."
    echo "Access Grafana at http://grafana.local (admin/mysecurepassword)"
    echo "Access Traefik dashboard at http://traefik.local"

elif [ "$1" == "uninstall" ]; then
    echo "Uninstalling DevOps Exercise..."

    # Clean up Terraform
    if [ -d "terraform" ]; then
        cd terraform
        terraform destroy -auto-approve
        cd ..
    fi

    # Delete Ingress Resources
    kubectl delete -f ingress-resources.yaml || true

    # Uninstall Helm releases
    helm uninstall postgres -n $NAMESPACE || true
    helm uninstall jenkins -n $NAMESPACE || true
    helm uninstall traefik -n $NAMESPACE || true
    helm uninstall grafana -n $NAMESPACE || true
    helm uninstall prometheus -n $NAMESPACE || true
    helm uninstall postgres-exporter -n $NAMESPACE || true

    # Delete namespace
    kubectl delete namespace $NAMESPACE

    echo "Uninstallation complete."

else
    echo "Usage: $0 {install|uninstall}"
    exit 1
fi