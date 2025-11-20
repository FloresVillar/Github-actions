# Pipe DevSecOps local-first (sin secretos, sin registries remotos, sin act)
# Uso típico:
#   make ensure-tools   # Verifica herramientas locales
#   make venv           # Crea entorno virtual de Python
#   make pipeline       # Ejecuta el pipeline completo DevSecOps local

SERVICE ?= python-microservice
IMAGE ?= $(SERVICE):dev

PY ?= python
PIP ?= python -m pip

# Herramientas necesarias (local-first, todo corre en tu máquina)

ensure-tools:
	@echo ">> Verificando herramientas locales requeridas (syft, grype, trivy, docker, kind, kubectl, semgrep, bandit, pip-audit, in-toto)..."
	@which docker >/dev/null || (echo "Falta 'docker' en el PATH" && exit 1)
	@which kind >/dev/null || (echo "Falta 'kind' en el PATH" && exit 1)
	@which kubectl >/dev/null || (echo "Falta 'kubectl' en el PATH" && exit 1)
	@which syft >/dev/null || echo "Instalar syft: https://github.com/anchore/syft"
	@which grype >/dev/null || echo "Instalar grype: https://github.com/anchore/grype"
	@which trivy >/dev/null || echo "Opcional: instalar trivy: https://github.com/aquasecurity/trivy"
	@which semgrep >/dev/null || echo "Instalar semgrep: pip install semgrep"
	@which bandit >/dev/null || echo "Instalar bandit: pip install bandit"
	@which pip-audit >/dev/null || echo "Instalar pip-audit: pip install pip-audit"
	@which in-toto-run >/dev/null || echo "Instalar in-toto: pip install in-toto"


# Entorno virtual de Python para desarrollo y herramientas

venv:
	@echo ">> Creando entorno virtual .venv e instalando dependencias de desarrollo"
	$(PY) -m venv .venv && . .venv/bin/activate && $(PIP) install -U pip -r requirements-dev.txt


# Build de la imagen Docker de la aplicación

build:
	@echo ">> Construyendo imagen Docker $(IMAGE)"
	docker build -t $(IMAGE) -f docker/Dockerfile .

# Pruebas unitarias (nivel código)

unit:
	@echo ">> Ejecutando pruebas unitarias con pytest"
	$(PY) -m pytest -q

# SAST: Análisis estático de seguridad (código fuente)

sast:
	@echo ">> SAST: ejecutando bandit y semgrep sobre el código fuente"
	bandit -r src -f json -o artifacts/bandit.json || true
	semgrep --config .semgrep.yml --error --json --output artifacts/semgrep.json || true

# SCA: Análisis de dependencias (Software Composition Analysis)

sca:
	@echo ">> SCA: auditando dependencias con pip-audit"
	pip-audit -r requirements.txt -f json -o artifacts/pip-audit.json || true

# SBOM: Bill of Materials del proyecto y de la imagen

sbom:
	@echo ">> Generando SBOM del proyecto (directorio) con syft"
	syft packages dir:. -o json > artifacts/sbom-syft-project.json || true
	@echo ">> Generando SBOM de la imagen Docker con syft"
	syft $(IMAGE) -o json > artifacts/sbom-syft-image.json || true


# Escaneo de vulnerabilidades de la imagen (container scanning)

scan-image:
	@echo ">> Analizando vulnerabilidades de la imagen con grype (salida SARIF)"
	grype $(IMAGE) -o sarif > artifacts/grype-image.sarif || true
	@echo ">> (Opcional) Escaneo de imagen con trivy si está instalado"
	@which trivy >/dev/null && trivy image --format sarif --output artifacts/trivy-image.sarif $(IMAGE) || true

# Docker Compose: levantar y bajar el servicio para pruebas locales

compose-up:
	@echo ">> Levantando servicios con docker compose y construyendo imagen si es necesario"
	docker compose up -d --build
	@sleep 2
	@echo ">> Verificando endpoint /health de la aplicación en modo compose"
	curl -sf http://127.0.0.1:8000/health | tee .evidence/compose-health.json

compose-down:
	@echo ">> Deteniendo servicios de docker compose y eliminando volúmenes"
	docker compose down -v

# DAST: Pruebas dinámicas con OWASP ZAP (desde contenedor)

dast:
	@echo ">> DAST: ejecutando OWASP ZAP baseline contra http://127.0.0.1:8000"
	docker run --rm -t --network host owasp/zap2docker-stable zap-baseline.py -t http://127.0.0.1:8000 -J artifacts/zap-baseline.json -r artifacts/zap-report.html || true

# Kubernetes local con kind

kind-up:
	@echo ">> Creando clúster kind 'devsecops' con configuración k8s/kind-config.yaml (si no existe)"
	kind create cluster --name devsecops --config k8s/kind-config.yaml || true

kind-load:
	@echo ">> Cargando la imagen local $(IMAGE) dentro del clúster kind 'devsecops'"
	kind load docker-image $(IMAGE) --name devsecops

# Despliegue en Kubernetes (manifiesto k8s/deployment.yaml)

k8s-deploy:
	@echo ">> Aplicando manifiestos Kubernetes desde k8s/deployment.yaml"
	kubectl apply -f k8s/deployment.yaml
	@echo ">> Esperando a que termine el rollout del deployment $(SERVICE)"
	kubectl rollout status deploy/$(SERVICE) --timeout=90s
	@echo ">> Listando pods (se guarda en .evidence/pods.txt)"
	kubectl get pods -o wide | tee .evidence/pods.txt

# Port-forward del servicio de Kubernetes hacia localhost

k8s-portforward:
	@echo ">> Redirigiendo el servicio $(SERVICE) al puerto localhost:30080 -> 8000 del contenedor"
	- pkill -f "kubectl port-forward service/$(SERVICE) 30080:8000" || true
	kubectl port-forward service/$(SERVICE) 30080:8000 >/dev/null 2>&1 &
	@sleep 2


# Prueba de humo contra el servicio expuesto por Kubernetes

smoke:
	@echo ">> Ejecutando prueba de humo contra /health en Kubernetes (localhost:30080)"
	curl -sf http://127.0.0.1:30080/health | tee .evidence/k8s-health.json


# Limpieza de recursos en Kubernetes y kind

k8s-destroy:
	@echo ">> Eliminando recursos Kubernetes definidos en k8s/deployment.yaml"
	kubectl delete -f k8s/deployment.yaml || true

kind-down:
	@echo ">> Eliminando clúster kind 'devsecops'"
	kind delete cluster --name devsecops || true

# in-toto: generar una atestación/procedencia simple (solo local)

attest:
	@echo ">> Creando una atestación de tipo in-toto (provenance local, sin claves reales)"
	in-toto-run --step-name "build" --products artifacts --key /dev/null --record-streams --local-run --signing-key-fob-data foo || true


# Empaquetar evidencias del pipeline (logs, reportes, SBOM, etc.)

evidence-pack:
	@echo ">> Empaquetando evidencias en artifacts/evidence-<timestamp>.tar.gz"
	tar -czf artifacts/evidence-$(shell date +%Y%m%d-%H%M%S).tar.gz artifacts .evidence


# Pipeline completo: desde build hasta evidencias (devsecops local-first)

pipeline: build unit sast sca sbom scan-image compose-up dast compose-down kind-up kind-load k8s-deploy k8s-portforward smoke attest evidence-pack

.PHONY: ensure-tools venv build unit sast sca sbom scan-image compose-up compose-down dast kind-up kind-load k8s-deploy k8s-portforward smoke k8s-destroy kind-down attest evidence-pack pipeline
