# ArgoCD is installed via Kustomize
# See: k8s/argocd/base/kustomization.yaml
#
# To install ArgoCD:
#   kubectl apply -k k8s/argocd/base
#
# To deploy the app-of-apps pattern:
#   kubectl apply -f k8s/argocd/app-of-apps.yaml
#
# This approach is preferred over Helm as it:
# - Uses official ArgoCD manifests
# - Is more GitOps-native
# - Easier to version control
# - No Terraform provider dependencies
