#!/usr/bin/env bash
# Genera certificados locales de prueba. Ejecutar desde la raíz del paquete.
# Requiere openssl y keytool. Ver README.md, sección 3.2, para la alternativa Docker.
# Toma las contraseñas del entorno o compose/.env.mtls, sin imprimirlas.
# ATENCIÓN: vuelve a crear ca/, server/ y clientes/. Invalida el material anterior.
# No utilizar la CA ni estos certificados para un entorno de producción.

set -euo pipefail

# Git Bash no debe transformar los nombres del certificado en rutas de Windows.
export MSYS_NO_PATHCONV=1

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ"

# El entorno tiene prioridad sobre el archivo. Se retira CR para admitir archivos Windows.
ENV_MTLS="$RAIZ/../../compose/.env.mtls"
for var in GATEWAY_KEYSTORE_PASSWORD GATEWAY_TRUSTSTORE_PASSWORD MTLS_CLIENTES_P12_PASSWORD; do
  if [ -z "${!var:-}" ] && [ -f "$ENV_MTLS" ]; then
    valor="$(grep -E "^${var}=" "$ENV_MTLS" | tail -n1 | cut -d= -f2- | tr -d '')"
    printf -v "$var" '%s' "$valor"
  fi
  if [ -z "${!var:-}" ] || [ "${!var}" = "changeit" ]; then
    echo "ERROR: falta $var (o vale 'changeit'). Definela en compose/.env.mtls, ver README.md" >&2
    exit 1
  fi
  export "$var"
done
# Comprobar herramientas antes de borrar los certificados existentes.
for cmd in openssl keytool; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: falta '$cmd' en el PATH (keytool viene con cualquier JDK 17+)." >&2
    echo "       Sin instalar nada, con Docker: ver README.md, seccion 3.2 (imagen eclipse-temurin:21-jdk)." >&2
    exit 1
  fi
done
DIAS=825   # limite de CA/Browser Forum; no importa aqui (uso interno de prueba) pero se respeta

rm -rf ca server clientes
mkdir -p ca server clientes

echo "== 1. CA de prueba =="
openssl req -x509 -newkey rsa:4096 -sha256 -days "$DIAS" -nodes \
  -keyout ca/ca-key.pem -out ca/ca-cert.pem \
  -subj "/O=IHE Gateway Dev/OU=mtls-certs de prueba/CN=ihe-gateway-test-ca"

echo "== 2. Certificado de servidor (el propio gateway) =="
openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout server/gateway-key.pem -out server/gateway.csr \
  -subj "/O=IHE Gateway Dev/OU=servidor/CN=ihe-gateway"

# MTLS_SERVER_SAN_EXTRA agrega nombres DNS o IP, separados por comas.
# Deben incluir el host de GATEWAY_PUBLIC_BASE_URL si se accede desde otro equipo.
SAN="DNS:ihe-gateway,DNS:localhost,IP:127.0.0.1${MTLS_SERVER_SAN_EXTRA:+,${MTLS_SERVER_SAN_EXTRA}}"
printf 'subjectAltName = %s
extendedKeyUsage = serverAuth
' "$SAN" > server/gateway-san.cnf
echo "   SAN: $SAN"

openssl x509 -req -sha256 -days "$DIAS" \
  -in server/gateway.csr -CA ca/ca-cert.pem -CAkey ca/ca-key.pem -CAcreateserial \
  -extfile server/gateway-san.cnf \
  -out server/gateway-cert.pem

rm -f server/gateway.csr server/gateway-san.cnf ca/ca-cert.srl

echo "== 3. Keystore PKCS12 del servidor (clave + cert + cadena) =="
openssl pkcs12 -export \
  -inkey server/gateway-key.pem -in server/gateway-cert.pem -certfile ca/ca-cert.pem \
  -name ihe-gateway \
  -out server/gateway-keystore.p12 -passout env:GATEWAY_KEYSTORE_PASSWORD
chmod 644 server/gateway-keystore.p12

echo "== 4. Truststore PKCS12 del servidor (solo la CA: con eso valida cualquier cliente firmado por ella) =="
keytool -importcert -noprompt -alias ihe-gateway-test-ca \
  -file ca/ca-cert.pem -keystore server/gateway-truststore.p12 \
  -storetype PKCS12 -storepass:env GATEWAY_TRUSTSTORE_PASSWORD

emitir_cliente() {
  local nombre="$1" cn="$2"
  openssl req -newkey rsa:2048 -sha256 -nodes \
    -keyout "clientes/${nombre}-key.pem" -out "clientes/${nombre}.csr" \
    -subj "/O=IHE Gateway Dev/OU=cliente de prueba/CN=${cn}"
  printf 'extendedKeyUsage = clientAuth\n' > "clientes/${nombre}-eku.cnf"
  openssl x509 -req -sha256 -days "$DIAS" \
    -in "clientes/${nombre}.csr" -CA ca/ca-cert.pem -CAkey ca/ca-key.pem -CAcreateserial \
    -extfile "clientes/${nombre}-eku.cnf" \
    -out "clientes/${nombre}-cert.pem"
  rm -f "clientes/${nombre}.csr" "clientes/${nombre}-eku.cnf"
  openssl pkcs12 -export \
    -inkey "clientes/${nombre}-key.pem" -in "clientes/${nombre}-cert.pem" -certfile ca/ca-cert.pem \
    -name "$nombre" \
    -out "clientes/${nombre}.p12" -passout env:MTLS_CLIENTES_P12_PASSWORD
}

echo "== 5. Cliente 'cliente-hcen' (fuente autorizada del dominio con formato HCEN urn:oid:2.16.858.2.99999999.72768.1, gateway/config/pixm-sources.yaml) =="
emitir_cliente "cliente-hcen" "cliente-hcen"

echo "== 6. Cliente 'cliente-test' (fuente autorizada del dominio TEST urn:oid:2.16.858.2.10002222.72768.1, gateway/config/pixm-sources.yaml) =="
emitir_cliente "cliente-test" "cliente-test"

# Clientes adicionales: nombre:CN separados por espacios. Se regeneran todos los clientes.
for par in ${MTLS_CLIENTES_EXTRA:-}; do
  nombre="${par%%:*}"; cn="${par#*:}"
  echo "== Cliente adicional '${nombre}' (CN=${cn}) =="
  emitir_cliente "$nombre" "$cn"
done

rm -f ca/ca-cert.srl

echo "== Listo =="
echo "Contrasenas de los almacenes PKCS12: las de compose/.env.mtls (no se imprimen)"
find ca server clientes -type f | sort
