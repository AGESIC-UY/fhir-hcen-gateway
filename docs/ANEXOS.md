# Anexos del Gateway HCEN

Estas instrucciones amplían el [tutorial](../README.md). Los ejemplos no requieren agregar dominios ni precargar recursos directamente en HAPI.

## Acceder desde otro equipo

La URL pública y el certificado deben referirse al mismo servidor. Por ejemplo, si los clientes utilizan `https://gateway.midominio.uy:8080/fhir`, se configura esa dirección en `GATEWAY_PUBLIC_BASE_URL` y se incluye el nombre al emitir los certificados:

```bash
MTLS_SERVER_SAN_EXTRA='DNS:gateway.midominio.uy' \
  bash security/mtls-certs/generar-certificados.sh
```

Para una IP, se utiliza la forma `IP:10.0.0.5`. Se pueden combinar nombres e IP separados por comas. Al ejecutar el generador mediante Docker, la variable se proporciona con `-e MTLS_SERVER_SAN_EXTRA='DNS:gateway.midominio.uy'` antes del nombre de la imagen.

El certificado incluye por defecto `localhost`, `127.0.0.1` e `ihe-gateway`. Para inspeccionar los nombres emitidos:

```bash
openssl x509 -in security/mtls-certs/server/gateway-cert.pem -noout -ext subjectAltName
```

El generador reemplaza todos los certificados. Después de regenerarlos, es necesario reiniciar el Gateway y actualizar la CA y el certificado en cada cliente.

## Agregar otro cliente de prueba

El certificado identifica al sistema que envía la petición. Para autorizarlo a registrar pacientes de un dominio, debe existir la asociación correspondiente en `gateway/config/pixm-sources.yaml`.

El generador admite clientes adicionales mediante `MTLS_CLIENTES_EXTRA`, con elementos `nombre:CN` separados por espacios:

```bash
MTLS_CLIENTES_EXTRA='his-hospital-a:his-hospital-a' \
  bash security/mtls-certs/generar-certificados.sh
```

Esto vuelve a emitir también los clientes de prueba originales. Por ello, agregar un cliente requiere considerar la sustitución del material ya entregado.

La identidad completa del certificado puede consultarse con:

```bash
openssl x509 -in security/mtls-certs/clientes/his-hospital-a-cert.pem \
  -noout -subject -nameopt RFC2253
```

El valor que aparece después de `subject=` debe coincidir con `cliente-autorizado`. Para preparar una nueva asociación, el responsable del despliegue necesita el dominio MRN autorizado y esa identidad. El formato del dominio debe cumplir la guía HCEN. Los ejemplos del tutorial ya tienen esta asociación preparada y no requieren cambios.

Cada dominio debe aparecer una sola vez. El archivo se lee al arrancar, por lo que una modificación requiere reiniciar el Gateway. Emitir un certificado por sí solo no autoriza un dominio nuevo.

## Configuración de referencia

| Parámetro o archivo | Qué representa |
| --- | --- |
| `GATEWAY_PUBLIC_BASE_URL` | Base que reciben los clientes en los enlaces de respuesta. |
| `GATEWAY_PORT` | Puerto publicado en el equipo. Si cambia, debe concordar con la URL de acceso y la configuración del cliente. |
| `HAPI_BASE_URL`, `VALIDATOR_BASE_URL` | Direcciones entre servicios Docker. No son las direcciones que utiliza el implementador. |
| `MHD_MAX_BUNDLE_MB` | Límite del envío completo. Esta entrega utiliza 8 MiB con validación activada. |
| `MHD_MAX_DOCUMENT_BUNDLE_MB` | Límite adicional del Bundle documental. No aumenta el límite del envío completo. |
| `MHD_PATIENT_CREATE_ENABLED` | Permite crear desde ITI-65 al paciente ausente. En este recorrido está activado. |
| `VALIDATION_ENABLED` | Activa la validación de recursos que realiza el Gateway. |
| `IG_FILE` | Archivo de la guía en `validator/igs/`. |
| `IG_DEPENDENCIES` | Paquetes adicionales que carga el validador. |
| `VALIDATOR_PORT` | Acceso al validador desde el equipo anfitrión. Por defecto, sólo `127.0.0.1:8081`. |
| `compose/.env.mtls` | Contraseñas de los almacenes del servidor y de los archivos de cliente PKCS12. |

Las opciones de terminología merecen una aclaración: en esta imagen, `DISABLE_TERMINOLOGY=true` reduce determinados avisos por códigos que no puede resolver, pero los bindings a ValueSets siguen interviniendo en la validación. `SUPPRESS_BINDING_WARNINGS=true` suprime ciertos avisos de bindings y `ANY_EXTENSIONS_ALLOWED=true` permite extensiones desconocidas. Un recurso aceptado no demuestra validación terminológica completa.

Para aplicar cambios de variables de entorno, utilizar `docker compose -f compose/docker-compose.yml up -d --wait`. Un simple `restart` no incorpora variables nuevas al contenedor. Para recargar un paquete sustituido en el directorio montado del validador, reiniciar `fhir-validator` después de comprobar su integridad.

## Cargar una nueva versión de la guía

El validador carga el paquete de la guía desde `validator/igs/`. Para utilizar una versión nueva:

1. Descargar el `package.tgz` de la versión deseada desde las versiones publicadas de la guía de implementación: <https://github.com/AGESIC-UY/uy-fhir-ig/releases>
2. Copiarlo en `validator/igs/`, reemplazando el anterior. Si se conserva otro nombre de archivo, indicarlo en `IG_FILE` de `compose/.env`.
3. Actualizar el hash del paquete y comprobar la integridad:

```bash
(cd validator/igs && sha256sum package.tgz > SHA256SUMS)
bash compose/verificar-integridad-ig.sh
```

4. Volver a levantar la instalación para que el validador cargue el paquete nuevo:

```bash
docker compose -f compose/docker-compose.yml up -d --wait
docker compose -f compose/docker-compose.yml restart fhir-validator
```

El validador tarda en quedar disponible mientras carga la guía. Los datos ya guardados en HAPI no se vuelven a validar.

## El validador de forma independiente

Desde el equipo que ejecuta Docker se puede enviar un recurso al servicio de validación:

```bash
curl --silent --show-error -X POST \
  http://127.0.0.1:8081/fhir-validator/validate \
  -H 'Content-Type: application/fhir+json' \
  --data-binary @set-pruebas/paciente.json
```

Este servicio comprueba el recurso, pero no lo registra ni ejecuta ITI-104 o ITI-65. Revisar los mensajes de validación del cuerpo de la respuesta. Que el servicio responda HTTP 200 no significa necesariamente que el recurso sea válido.

## Acceso directo a HAPI

HAPI guarda los recursos de esta PoC. No publica un puerto al exterior y se accede desde la red interna de Docker. Este acceso sirve para inspección o preparación local y no forma parte de las transacciones de Plataforma.

Una escritura directa evita la validación y las reglas que aplica el Gateway. Por eso no debe utilizarse para demostrar que una publicación HCEN funciona ni para corregir silenciosamente un caso rechazado.

### Preparar el acceso

La siguiente función usa curl dentro de la imagen del validador ya descargada. En Bash, desde la raíz del paquete:

```bash
RED=ihe-gateway_backend
CURL_IMG=$(sed -n 's/^VALIDATOR_IMAGE=//p' compose/.env | tr -d '\r')
HAPI=http://hapi-fhir:8080/fhir
hapi() {
  MSYS_NO_PATHCONV=1 docker run --rm -i --network "$RED" \
    --entrypoint curl "$CURL_IMG" --silent --show-error "$@"
}
hapi -o /dev/null -w '%{http_code}\n' "$HAPI/metadata"
```

Se espera HTTP 200. Si Compose se inició con otro nombre de proyecto, la red también cambia. El comando `docker network ls` permite identificar la red `backend` de esa instalación y ajustar el valor de `RED`. El contenedor auxiliar se elimina al terminar cada comando. La entrada estándar permite utilizar archivos sin montar carpetas, también desde Git Bash.

### Consultar los datos locales

Para comprobar el paciente utilizado en CA-02, CA-06 o CA-07:

```bash
hapi -H 'Cache-Control: no-cache' \
  "$HAPI/Patient?identifier=urn:oid:2.16.858.2.99999999.72768.1%7C1873455"
```

La búsqueda devuelve un Bundle. Revisar que exista una sola entrada Patient y, en CA-06, que su `telecom` contenga el teléfono actualizado.

También es posible consultar recursos de contexto por su identificador o por un id local obtenido de una respuesta. El acceso de este anexo es al almacenamiento de la PoC, no a una API pública adicional de HCEN.

### Cargar datos de referencia, sólo cuando la prueba lo requiera

Los ejemplos del tutorial ya envían Organization, Practitioner y PractitionerRole en ITI-65. No necesitan esta carga previa.

Si otra prueba requiere una precarga, preparar recursos que cumplan los perfiles de la guía. Como punto de partida se pueden utilizar los recursos de contexto de `set-pruebas/publicacion.json`. Utilizar un Bundle `transaction` cuando existan referencias entre las entradas, con `fullUrl` y referencias coherentes. Para Organization y Practitioner, una actualización condicional por su identificador evita crear duplicados al repetir la carga. Para PractitionerRole, definir un id estable propio de la prueba.

Una vez preparado y revisado ese archivo:

```bash
hapi -i -X POST "$HAPI" -H 'Content-Type: application/fhir+json' \
  --data-binary @- < recursos-iniciales.json
```

`recursos-iniciales.json` es un archivo que prepara quien realiza esa prueba adicional, no un archivo incluido en el tutorial. Revisar el estado por entrada en la respuesta. Una escritura aceptada por HAPI no sustituye la validación del intercambio HCEN.

### Corregir o eliminar datos locales

Para corregir un recurso de referencia, se repite su PUT con el estado completo actualizado y la misma identidad. HAPI comprueba referencias entre recursos, por lo que eliminar un recurso todavía referenciado puede fallar.

La eliminación no es un paso del tutorial. La limpieza de datos requiere identificar primero qué recursos y documentos dependen de ellos y limitar la operación a la instalación de prueba. No se propone borrar volúmenes para continuar un caso que falló.
