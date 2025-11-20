import os
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

# Puerto HTTP obtenido de la variable de entorno PORT (por defecto 8000)
PORT = int(os.environ.get("PORT", "8000"))

# Nombre lógico del servicio, configurable por variable de entorno
# Esto permite reutilizar el mismo código para varios microservicios
SERVICE_NAME = os.environ.get("SERVICE_NAME", "python-microservice")


class Handler(BaseHTTPRequestHandler):
    """Manejador HTTP mínimo para un microservicio sencillo."""

    def _send(self, code, payload, content_type="application/json"):
        """
        Envia una respuesta HTTP estándar.

        Parámetros:
        - code: código de estado HTTP (200, 404, etc.).
        - payload: diccionario (se serializa a JSON) o bytes.
        - content_type: tipo de contenido de la respuesta.
        """
        # Si el payload NO es bytes, lo convertimos a JSON y luego a bytes
        body = payload if isinstance(payload, (bytes, bytearray)) else json.dumps(payload).encode()

        # Cabeceras básicas de la respuesta HTTP
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

        # Envío del cuerpo al cliente
        self.wfile.write(body)

    def do_GET(self):
        """
        Maneja solicitudes GET.

        Endpoints expuestos:
        - "/"         → información básica del servicio
        - "/health"   → endpoint de salud (para Docker / Kubernetes / pruebas)
        """
        if self.path == "/" or self.path == "/":
            # Respuesta principal: identifica el servicio y marca ok=True
            self._send(200, {"service": SERVICE_NAME, "ok": True})
        elif self.path == "/health":
            # Endpoint de salud usado por healthchecks y pruebas de humo
            self._send(200, {"status": "healthy"})
        else:
            # Cualquier otra ruta devuelve 404 Not Found
            self._send(404, {"error": "not found"})


def main():
    """
    Punto de entrada del microservicio.

    Crea un servidor HTTP que escucha en 0.0.0.0:PORT usando Handler,
    para que sea accesible desde contenedores Docker o Kubernetes.
    """
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    # Mensaje de arranque en español (incluyendo el nombre del servicio)
    print(f"Sirviendo el servicio '{SERVICE_NAME}' en http://0.0.0.0:{PORT} (CTRL+C para detener)")

    try:
        # Bucle principal: atiende peticiones hasta que se interrumpe el proceso
        server.serve_forever()
    except KeyboardInterrupt:
        # Permite detener el servidor limpiamente con CTRL+C
        print("\nServidor detenido por KeyboardInterrupt (CTRL+C).")
    finally:
        # Cierra el socket del servidor de forma ordenada
        server.server_close()
        print("Conexiones cerradas. Servidor apagado correctamente.")


if __name__ == "__main__":
    main()
