import http.client
import os
import subprocess
import time

def test_health_endpoint():
    """
    Prueba de integración mínima del endpoint /health.

    - Levanta el servidor como un subproceso usando `python -m src.app`.
    - Fuerza el puerto 8090 mediante la variable de entorno PORT.
    - Realiza una petición HTTP GET a /health.
    - Verifica que el código de respuesta sea 200.
    - Finalmente detiene el subproceso (servidor).
    """

    print(">> Iniciando prueba del endpoint /health en 127.0.0.1:8090")

    # Copiamos el entorno actual para no perder variables existentes
    env = os.environ.copy()
    # Forzamos el uso del puerto 8090 para esta prueba
    env["PORT"] = "8090"

    # Lanzamos el servidor como subproceso ejecutando el módulo src.app
    print(">> Lanzando servidor como subproceso con 'python -m src.app' en el puerto 8090")
    p = subprocess.Popen(["python", "-m", "src.app"], env=env)

    try:
        # Pequeña espera para darle tiempo al servidor a arrancar
        print(">> Esperando a que el servidor arranque...")
        time.sleep(1.5)

        # Creamos una conexión HTTP hacia localhost:8090
        print(">> Creando conexión HTTP a 127.0.0.1:8090")
        conn = http.client.HTTPConnection("127.0.0.1", 8090, timeout=3)

        # Enviamos petición GET al endpoint /health
        print(">> Enviando petición GET a /health")
        conn.request("GET", "/health")

        # Obtenemos la respuesta del servidor
        resp = conn.getresponse()
        print(f">> Respuesta recibida: status={resp.status}, reason={resp.reason}")

        # Aseguramos que el código de estado sea 200 (OK)
        assert resp.status == 200, f"Se esperaba status 200 y se obtuvo {resp.status}"

        # Cerramos explícitamente la conexión HTTP
        conn.close()
        print(">> Conexión HTTP cerrada correctamente")

    finally:
        # Detenemos el proceso del servidor, incluso si la aserción falla
        print(">> Deteniendo servidor de prueba (subproceso)...")
        p.terminate()
        p.wait(timeout=5)
        print(">> Servidor detenido correctamente")
