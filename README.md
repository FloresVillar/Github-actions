### Laboratorio CI/CD DevSecOps con github-actions

Este repositorio entrega un pipeline completo de **DevSecOps** para un microservicio **Python** mínimo basado en `http.server`, con **Docker**, **Kubernetes (KinD)** y **GitHub Actions**. No usa `GITHUB_TOKEN` implícito, no requiere contraseñas ni secretos, y puede ejecutarse **100% local** con `Makefile`.

#### Estructura

- `src/` servicio HTTP (`/` y `/health`).
- `tests/` pruebas unitarias.
- `docker/` Dockerfile no-root y `HEALTHCHECK`.
- `compose.yaml` levantar servicio local para DAST.
- `k8s/` manifiestos y `kind-config.yaml`.
- `.github/workflows/ci-devsecops.yml` pipeline CI.
- `artifacts/` resultados de análisis (SBOM, SAST, SCA, DAST, scans).
- `.evidence/` evidencias (smoke tests, pods, etc.).
- `slsa/` ejemplo de layout para in-toto.
- `Makefile` tareas locales.

#### Requisitos locales

- Docker, Kind, kubectl
- Python 3.12
- Herramientas: `syft`, `grype`, `semgrep`, `bandit`, `pip-audit`, `in-toto-run`, (opcional `trivy`).
  > Instálalas según tu SO. El target `make ensure-tools` te indica faltantes.

#### Flujo local recomendado

```bash
make build           # construye imagen
make unit            # pruebas unitarias
make sast sca        # SAST + SCA
make sbom            # SBOM proyecto + imagen
make scan-image      # análisis de vulnerabilidades imagen
make compose-up      # lanza app en :8000
make dast            # ZAP baseline contra http://127.0.0.1:8000
make compose-down
make kind-up         # crea cluster KinD
make kind-load       # carga imagen local al cluster
make k8s-deploy      # despliega y espera rollout
make k8s-portforward # 127.0.0.1:30080 -> service
make smoke           # verifica /health en K8s
make attest          # ejemplo in-toto (local)
make evidence-pack   # tar.gz con artefactos y evidencias
```

#### GitHub Actions: conceptos clave

- **Workflow**: `.github/workflows/ci-devsecops.yml`. Se ejecuta en `push`, `pull_request` o manual via `workflow_dispatch`.
- **Jobs**: 1 job `pipeline` en `ubuntu-latest`.
- **Steps**: checkout, set up Python, construir imagen, pruebas, SAST/SCA, SBOM, escaneo de imagen, levantar `compose` y correr ZAP, recolectar artefactos.
- **Runners**: usa hosted runner; no requiere secretos.
- **Eventos y triggers**: definidos en la clave `on:` del workflow.
- **Secretos y variables**: **No requeridos** en este laboratorio. Evitamos pushes/registries externos.

#### Supply Chain (local)

- **SBOM** con `syft` (proyecto e imagen).
- **SCA** con `pip-audit`.
- **SAST** con `bandit` y `semgrep` custom `.semgrep.yml`.
- **Escaneo de imagen** con `grype` (y opcional `trivy`).
- **DAST** con `OWASP ZAP baseline` sobre servicio local/compose.
- **SLSA-like**: demostración de **in-toto** para registrar una evidencia del paso `build`.

#### Buenas prácticas incluidas

- Imagen **no root** y `slim` base.
- `HEALTHCHECK` en Docker y probes en K8s.
- Evidencias y artefactos en carpetas dedicadas.
- `imagePullPolicy: Never` + `kind load docker-image` para **KinD** offline.
- Port-forward para smoke tests sin exponer NodePort.

> Tip: Este repo puede integrarse a un **tablero Kanban** (Backlog -> Ready -> In Progress -> Code Review -> Testing -> Done) y capturar métricas (builds fallidos/exitosos, vulnerabilidades encontradas/mitigadas, etc.).
