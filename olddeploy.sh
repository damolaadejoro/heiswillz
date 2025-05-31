#!/bin/bash

NAMESPACE="devops-exercise"

if [ "$1" == "install" ]; then
    echo "Installing DevOps Exercise..."

    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

    # Deploy PostgreSQL
    kubectl apply -f postgres-secret.yaml
    helm install postgres bitnami/postgresql -n $NAMESPACE -f values-postgres.yaml

    # Deploy Jenkins
    helm install jenkins jenkins/jenkins -n $NAMESPACE -f values-jenkins.yaml

    # Deploy Traefik
    helm install traefik traefik/traefik -n $NAMESPACE

    # Deploy Grafana
    helm install grafana grafana/grafana -n $NAMESPACE -f values-grafana.yaml

    # Wait for Grafana to be ready
    echo "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n $NAMESPACE --timeout=300s

    # Start port-forwarding for Grafana
    echo "Starting port-forwarding for Grafana..."
    kubectl port-forward svc/grafana -n $NAMESPACE 3000:80 &
    sleep 5  # Give port-forwarding a moment to establish

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

    echo "Installation complete. Update /etc/hosts with Minikube IP for jenkins.local, traefik.local, grafana.local."
    echo "Minikube IP: $(minikube ip)"
    echo "Configure Jenkins Job DSL at http://jenkins.local and run SeedJob."

elif [ "$1" == "uninstall" ]; then
    echo "Uninstalling DevOps Exercise..."

    # Clean up Terraform
    if [ -d "terraform" ]; then
        cd terraform
        terraform destroy -auto-approve
        cd ..
    fi

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