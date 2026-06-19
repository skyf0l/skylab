variable "cluster_name" {
  type        = string
  description = "Cluster name; top-level prefix for secret paths (kvv2/data/cluster/<cluster_name>/...). Scopes the ESO and workload read policies."
  default     = "skylab"
}

# In-cluster Kubernetes API server, as reached from the Vault pods. Vault uses
# its own pod ServiceAccount token + the in-cluster CA to call TokenReview
# (no static reviewer JWT/CA needed — see auth.tf).
variable "kubernetes_auth_backend_kubernetes_host" {
  type        = string
  description = "URL to the base of the Kubernetes API server, as reached from the Vault pods."
  default     = "https://kubernetes.default.svc"
}
