# Local-first DevSecOps pipeline (no secrets, no registries, no act)
SERVICE ?= python-microservice
IMAGE ?= $(SERVICE):dev

PY ?= python
PIP ?= python -m pip

ensure-tools:
	@echo ">> Ensuring local tools (syft, grype, trivy, docker, kind, kubectl, semgrep, bandit, pip-audit, in-toto)..."
	@which docker >/dev/null || (echo "docker required" && exit 1)
	@which kind >/dev/null || (echo "kind required" && exit 1)
	@which kubectl >/dev/null || (echo "kubectl required" && exit 1)
	@which syft >/dev/null || echo "Install syft: https://github.com/anchore/syft"
	@which grype >/dev/null || echo "Install grype: https://github.com/anchore/grype"
	@which trivy >/dev/null || echo "Optional: Install trivy: https://github.com/aquasecurity/trivy"
	@which semgrep >/dev/null || echo "Install semgrep: pip install semgrep"
	@which bandit >/dev/null || echo "Install bandit: pip install bandit"
	@which pip-audit >/dev/null || echo "Install pip-audit: pip install pip-audit"
	@which in-toto-run >/dev/null || echo "Install in-toto: pip install in-toto"

venv:
	$(PY) -m venv .venv && . .venv/bin/activate && $(PIP) install -U pip -r requirements-dev.txt

build:
	@echo ">> Building image $(IMAGE)"
	docker build -t $(IMAGE) -f docker/Dockerfile .

unit:
	@echo ">> Running unit tests"
	$(PY) -m pytest -q

sast:
	@echo ">> SAST: bandit + semgrep"
	bandit -r src -f json -o artifacts/bandit.json || true
	semgrep --config .semgrep.yml --error --json --output artifacts/semgrep.json || true

sca:
	@echo ">> SCA (pip-audit)"
	pip-audit -r requirements.txt -f json -o artifacts/pip-audit.json || true

sbom:
	@echo ">> SBOM with syft"
	syft packages dir:. -o json > artifacts/sbom-syft-project.json || true
	syft $(IMAGE) -o json > artifacts/sbom-syft-image.json || true

scan-image:
	@echo ">> Vulnerability scan with grype"
	grype $(IMAGE) -o sarif > artifacts/grype-image.sarif || true
	@echo ">> (Optional) trivy image scan"
	@which trivy >/dev/null && trivy image --format sarif --output artifacts/trivy-image.sarif $(IMAGE) || true

compose-up:
	docker compose up -d --build
	@sleep 2
	curl -sf http://127.0.0.1:8000/health | tee .evidence/compose-health.json

compose-down:
	docker compose down -v

dast:
	@echo ">> DAST with OWASP ZAP baseline (dockerized)"
	docker run --rm -t --network host owasp/zap2docker-stable zap-baseline.py -t http://127.0.0.1:8000 -J artifacts/zap-baseline.json -r artifacts/zap-report.html || true

kind-up:
	kind create cluster --name devsecops --config k8s/kind-config.yaml || true

kind-load:
	kind load docker-image $(IMAGE) --name devsecops

k8s-deploy:
	kubectl apply -f k8s/deployment.yaml
	@echo ">> Wait for rollout"
	kubectl rollout status deploy/$(SERVICE) --timeout=90s
	kubectl get pods -o wide | tee .evidence/pods.txt

k8s-portforward:
	@echo ">> Port-forward service to localhost:30080"
	- pkill -f "kubectl port-forward service/$(SERVICE) 30080:8000" || true
	kubectl port-forward service/$(SERVICE) 30080:8000 >/dev/null 2>&1 &
	@sleep 2

smoke:
	curl -sf http://127.0.0.1:30080/health | tee .evidence/k8s-health.json

k8s-destroy:
	kubectl delete -f k8s/deployment.yaml || true

kind-down:
	kind delete cluster --name devsecops || true

attest:
	@echo ">> Create simple in-toto provenance (local only)"
	in-toto-run --step-name "build" --products artifacts --key /dev/null --record-streams --local-run --signing-key-fob-data foo || true

evidence-pack:
	@echo ">> Packing evidence"
	tar -czf artifacts/evidence-$(shell date +%Y%m%d-%H%M%S).tar.gz artifacts .evidence

# A convenient all-in-one
pipeline: build unit sast sca sbom scan-image compose-up dast compose-down kind-up kind-load k8s-deploy k8s-portforward smoke attest evidence-pack

.PHONY: ensure-tools venv build unit sast sca sbom scan-image compose-up compose-down dast kind-up kind-load k8s-deploy k8s-portforward smoke k8s-destroy kind-down attest evidence-pack pipeline
