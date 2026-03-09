# ═══════════════════════════════════════════════════════════════════════════════
# Makefile — KubeStation image build & deploy
# Usage:
#   make build            Build the image locally
#   make push             Push to registry
#   make deploy           Deploy to Kubernetes (statefulset by default)
#   make logs             Tail pod logs
#   make exec             Exec into pod
#
# Registry examples:
#   REGISTRY=myacr.azurecr.io          (Azure Container Registry)
#   REGISTRY=ghcr.io/my-org            (GitHub Container Registry)
#   REGISTRY=docker.io/my-org          (Docker Hub)
#
# Persistence modes:
#   make deploy                         (persistent — uses statefulset.yaml)
#   make deploy MANIFEST=deployment.yaml  (ephemeral — uses deployment.yaml)
# ═══════════════════════════════════════════════════════════════════════════════

REGISTRY    ?= ghcr.io/sriganesh040194
IMAGE_NAME  ?= kubestation
TAG         ?= latest
NAMESPACE   ?= default
APP_NAME    ?= kubestation
MANIFEST    ?= statefulset.yaml

# Pod name differs by workload type: StatefulSet uses <name>-0, Deployment uses random suffix
ifeq ($(MANIFEST),statefulset.yaml)
  POD_NAME  ?= $(APP_NAME)-0
  WORKLOAD  := statefulset
else
  POD_NAME  ?= $(shell kubectl get pod -n $(NAMESPACE) -l app=$(APP_NAME) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  WORKLOAD  := deployment
endif

FULL_IMAGE  := $(REGISTRY)/$(IMAGE_NAME):$(TAG)

.PHONY: build push release deploy logs exec delete purge status rebuild login

## Build Docker image
build:
	docker build \
	  --platform linux/amd64 \
	  -t $(FULL_IMAGE) \
	  -t $(IMAGE_NAME):$(TAG) \
	  -f Dockerfile .
	@echo "✓ Built: $(FULL_IMAGE)"

## Authenticate with the container registry (override per registry type)
## Examples:
##   ACR:  az acr login --name <registry-name>
##   GHCR: echo $CR_PAT | docker login ghcr.io -u <username> --password-stdin
##   Hub:  docker login docker.io
login:
	@echo "Override the 'login' target for your registry. See comments above."

## Push image to registry
push:
	docker push $(FULL_IMAGE)
	@echo "✓ Pushed: $(FULL_IMAGE)"

## Build and push in one step
release: build push

## Deploy to Kubernetes
## Persistent (default): make deploy
## Ephemeral:            make deploy MANIFEST=deployment.yaml
deploy:
	@echo "Deploying $(MANIFEST) ($(WORKLOAD)) to namespace $(NAMESPACE)..."
	sed \
	  -e 's|ghcr.io/sriganesh040194/kubestation:latest|$(FULL_IMAGE)|g' \
	  -e 's|namespace: default|namespace: $(NAMESPACE)|g' \
	  $(MANIFEST) | kubectl apply -f -
	kubectl rollout status $(WORKLOAD)/$(APP_NAME) -n $(NAMESPACE)

## Tail pod logs
logs:
	kubectl logs -f $(POD_NAME) -n $(NAMESPACE)

## Exec into pod
exec:
	kubectl exec -it $(POD_NAME) -n $(NAMESPACE) -- bash

## Delete workload (keeps PVC if StatefulSet)
delete:
	kubectl delete $(WORKLOAD) $(APP_NAME) -n $(NAMESPACE) --ignore-not-found
ifeq ($(WORKLOAD),statefulset)
	kubectl delete service $(APP_NAME) -n $(NAMESPACE) --ignore-not-found
endif

## Delete workload AND PVCs (StatefulSet only — full reset)
purge: delete
ifeq ($(WORKLOAD),statefulset)
	kubectl delete pvc data-$(APP_NAME)-0 -n $(NAMESPACE) --ignore-not-found
	@echo "⚠ PVC deleted — all /data contents are gone"
endif

## Show pod/workload status
status:
	kubectl get $(WORKLOAD),pods,pvc -n $(NAMESPACE) -l app=$(APP_NAME)

## Build without cache (force fresh download of all tools)
rebuild:
	docker build \
	  --platform linux/amd64 \
	  --no-cache \
	  -t $(FULL_IMAGE) \
	  -f Dockerfile .
