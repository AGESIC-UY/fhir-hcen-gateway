# Gateway HCEN: primeras pruebas de intercambio FHIR

Con el Gateway HCEN podés probar en un entorno local el intercambio de pacientes y documentos clínicos que propone la guía de implementación. Los ejemplos incluidos acompañan los primeros pasos: permiten enviar peticiones, conocer sus respuestas y preparar la integración de tu sistema.

El Gateway recibe las peticiones, aplica los controles del intercambio y utiliza un servidor HAPI FHIR para guardar los datos de prueba. Un servicio de validación comprueba los recursos contra la guía de implementación. Docker Compose inicia estos componentes y su base de datos juntos.

La instalación es una prueba de concepto (PoC). No se conecta a Plataforma ni registra información en ella. Las pruebas deben realizarse con datos sintéticos. Algunas diferencias de funcionamiento son necesarias para que los documentos puedan guardarse y recuperarse en este entorno local.

## Recorrido de prueba

El recorrido comienza con cuatro pasos: registrar un paciente, publicar un documento, buscarlo y recuperar su contenido. Cada transacción tiene un número ITI que permite identificarla en la guía de implementación.

| Paso | Transacción | Para qué sirve |
| --- | --- | --- |
| Registrar un paciente | ITI-104 | Comunicar la identificación y los datos del paciente del prestador. |
| Publicar un documento | ITI-65 | Enviar el documento clínico y los metadatos que permiten encontrarlo. |
| Buscar el documento | ITI-67 | Consultar sus metadatos y obtener la dirección para recuperarlo. |
| Recuperar el contenido | ITI-68 | Descargar la representación FHIR o el CDA del mismo documento. |

El recorrido se complementa con casos de actualización del paciente y publicación sin registro previo. ITI-104 es el paso recomendado, pero ITI-65 también puede crear al paciente que todavía no existe.

### Conceptos básicos

Un **recurso FHIR** es una estructura de datos con un propósito concreto. Por ejemplo, `Patient` representa al paciente y `DocumentReference` describe un documento. Los ejemplos se envían como JSON.

Un **Bundle** agrupa recursos. El Bundle de publicación contiene los metadatos, el contexto y otro Bundle con el documento clínico. Este último comienza con una `Composition`, que organiza el contenido de la consulta.

El **MRN** es el identificador de paciente dentro de un dominio de la institución. Se utilizan juntos el dominio (`system`) y el número (`value`). El certificado de cliente está autorizado para un dominio determinado. Los ejemplos ya incluyen valores compatibles con el cliente de prueba `cliente-hcen`.

El **CDA** es la representación XML del documento clínico. Para almacenarla en esta PoC se incluye un recurso `Binary`: sus bytes están codificados en base64 dentro del JSON. Al recuperar CDA, se recibe el XML directamente.

## 1. Preparar el equipo

Se requiere Docker Engine con Compose v2.24 o posterior y acceso al registro de imágenes. Si trabajás en Windows, podés utilizar Docker Desktop con contenedores Linux. Es necesario disponer de varios GB de memoria y espacio de disco para las imágenes y los datos. El primer arranque puede tardar varios minutos.

Los comandos del tutorial utilizan **Bash**. En Windows, se ejecutan desde WSL o Git Bash, en lugar de PowerShell. Para las peticiones HTTP también se puede utilizar Postman.

La generación de certificados utiliza `openssl` y `keytool`, incluido en un JDK 17 o posterior. Si estas herramientas no están instaladas, la sección de certificados incluye una alternativa mediante Docker.

Para comenzar, abrí una terminal en la carpeta principal del Gateway, donde se encuentran `compose/`, `security/` y `set-pruebas/`. Todos los comandos del tutorial se ejecutan desde esa ubicación.

| Ruta | Contenido |
| --- | --- |
| `compose/.env` | Valores del despliegue, como contraseña y dirección pública. |
| `compose/docker-compose.yml` | Servicios que inicia Docker. |
| `gateway/config/pixm-sources.yaml` | Asociación entre dominios MRN y certificados autorizados. |
| `security/mtls-certs/` | Generador y archivos de certificados locales. |
| `validator/igs/` | Paquete de la guía que carga el validador. |
| `set-pruebas/` | Cuerpos JSON de las peticiones y su procedencia. |
| `docs/` | Casos de prueba y anexos con info adicional. |

## 2. Completar la configuración

Antes del primer inicio, revisá estos dos valores de `compose/.env`:

| Variable | Qué completar |
| --- | --- |
| `POSTGRES_PASSWORD` | Definir una contraseña local para la base de datos. El archivo se entrega con este valor vacío y Docker no inicia sin él. |
| `GATEWAY_PUBLIC_BASE_URL` | Dirección por la que el cliente accede al Gateway. Para probar desde el mismo equipo, el valor es `https://localhost:8080/fhir`. |

La dirección pública se utiliza en los enlaces de las respuestas. Si otro equipo va a consumir el Gateway, `localhost` apuntaría a ese otro equipo: se debe utilizar el nombre o IP del servidor e incluirlo en el certificado como se explica en el anexo.

Los demás valores ya están preparados para el recorrido inicial. La conexión utiliza HTTPS con certificado de cliente y la validación FHIR está activada. Los nombres técnicos de algunas variables provienen del producto de origen y se mantienen para que la configuración funcione.

## 3. Preparar los certificados

La conexión utiliza **TLS mutuo (mTLS)**. El cliente comprueba la identidad del servidor y el servidor comprueba la del cliente. Por eso todas las peticiones, incluida la comprobación inicial, necesitan un certificado de cliente.

### 3.1 Crear las contraseñas

El primer paso es crear las contraseñas que protegen los almacenes de certificados y guardarlas en `compose/.env.mtls`. Para una instalación nueva, el siguiente comando genera los tres valores desde Bash con openssl:

```bash
for nombre in GATEWAY_KEYSTORE_PASSWORD GATEWAY_TRUSTSTORE_PASSWORD MTLS_CLIENTES_P12_PASSWORD; do
  echo "$nombre=$(openssl rand -hex 32)"
done > compose/.env.mtls
chmod 600 compose/.env.mtls
```

Si preferís utilizar Docker, este comando genera los mismos tres valores:

```bash
docker run --rm eclipse-temurin:21-jdk bash -c 'for nombre in GATEWAY_KEYSTORE_PASSWORD GATEWAY_TRUSTSTORE_PASSWORD MTLS_CLIENTES_P12_PASSWORD; do echo "$nombre=$(openssl rand -hex 32)"; done' > compose/.env.mtls
```

Elegí una de las dos alternativas. Ambos comandos reemplazan `.env.mtls`; en una instalación existente, ese cambio requiere preparar también la renovación de certificados. El archivo debe conservarse localmente y no incorporarse a Git.

### 3.2 Generar los archivos

Una vez creadas las contraseñas, el siguiente comando genera los certificados con openssl y keytool instalados:

```bash
bash security/mtls-certs/generar-certificados.sh
```

Para generarlos mediante Docker, en Linux o WSL:

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/w -w /w \
  eclipse-temurin:21-jdk bash security/mtls-certs/generar-certificados.sh
```

En Windows con Git Bash, el montaje se expresa con la ruta de Windows:

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W)":/w -w /w \
  eclipse-temurin:21-jdk bash security/mtls-certs/generar-certificados.sh
```

**El generador reemplaza la CA y todos los certificados anteriores.** Al regenerarlos, los clientes deben recibir el material nuevo. Para otros nombres de servidor o clientes, la configuración se explica en el [anexo de configuración](docs/ANEXOS.md).

### 3.3 Reconocer los archivos

| Archivo, dentro de `security/mtls-certs/` | Uso |
| --- | --- |
| `ca/ca-cert.pem` | Permite al cliente confiar en el certificado del servidor. |
| `clientes/cliente-hcen-cert.pem` y `clientes/cliente-hcen-key.pem` | Certificado y clave del cliente utilizado por curl. |
| `clientes/cliente-hcen.p12` | Alternativa para Postman u otros clientes que utilizan PKCS12. Contiene certificado y clave. |
| `server/gateway-keystore.p12` y `server/gateway-truststore.p12` | Almacenes del servidor. Docker los monta automáticamente. |
| `ca/ca-key.pem` | Clave que emite los certificados. No se entrega a los clientes. |

Los certificados generados sirven para estas pruebas locales. La contraseña del archivo de cliente `.p12` es `MTLS_CLIENTES_P12_PASSWORD`. Si se entrega ese archivo a otra persona, la contraseña debe comunicarse por un canal distinto.

## 4. Iniciar y comprobar la instalación

Antes de iniciar los servicios, comprobá la integridad de los paquetes FHIR incluidos:

```bash
bash compose/verificar-integridad-ig.sh
```

Si la comprobación informa una diferencia, el paquete y su `SHA256SUMS` deben revisarse para confirmar que correspondan a la misma entrega. Cuando la verificación termine correctamente, el entorno se inicia con:

```bash
docker compose -f compose/docker-compose.yml up -d --wait
docker compose -f compose/docker-compose.yml ps
```

Los servicios de larga duración deben aparecer en ejecución y saludables (`healthy`). El servicio auxiliar `binstore-init` termina después de preparar el almacenamiento, lo que es normal. El primer inicio puede tardar más porque descarga imágenes e inicializa la base de datos.

Si el inicio no termina correctamente, los mensajes de los servicios ayudan a identificar el problema:

```bash
docker compose -f compose/docker-compose.yml logs --tail=80 ihe-gateway hapi-fhir fhir-validator
```

## 5. Preparar el cliente HTTP

### Bash con curl

Para enviar las peticiones con curl, definí la dirección y los certificados en la terminal que se utilizará para las pruebas:

```bash
BASE=https://localhost:8080/fhir
CLIENTE=(curl --silent --show-error
  --cacert security/mtls-certs/ca/ca-cert.pem
  --cert security/mtls-certs/clientes/cliente-hcen-cert.pem
  --key security/mtls-certs/clientes/cliente-hcen-key.pem)
```

Los casos utilizan `"${CLIENTE[@]}"` para reutilizar esas opciones en cada petición. Al abrir una terminal nueva, es necesario definirlas otra vez. El certificado `cliente-hcen` corresponde al dominio MRN de los ejemplos, `urn:oid:2.16.858.2.99999999.72768.1`.

En Windows, las posibilidades de cargar certificados dependen de la distribución de curl y su biblioteca TLS. Si aparecen errores de importación, la distribución utilizada puede identificarse con `curl --version`. El recorrido puede ejecutarse desde WSL con curl compatible con los archivos PEM, o mediante Postman. La comprobación del certificado debe permanecer activada.

### Postman

En la configuración de Postman se debe registrar la CA `ca-cert.pem` y agregar un certificado de cliente para el host `localhost` y puerto `8080`. El archivo de cliente es `cliente-hcen.p12`, con su contraseña. Para otro servidor, se deben indicar su host y puerto.

Cada caso indica método, dirección, cabeceras y cuerpo. Cuando el cuerpo sea JSON, se utiliza el archivo indicado como contenido de la petición. ITI-67 utiliza un formulario `x-www-form-urlencoded`. La descripción del caso y `procedencia.json` no se envían al Gateway.

## 6. Ejecutar el recorrido

Con la instalación lista, el siguiente paso es abrir el [catálogo de casos de prueba](docs/CASOS-DE-PRUEBA.md). Conviene comenzar por CA-01 a CA-05, en ese orden: conexión, registro del paciente, publicación, búsqueda y recuperación de FHIR y CDA. Cada caso incluye la petición y el resultado esperado. Después se pueden explorar las variantes y los controles de error.

Los ejemplos están preparados para una instalación sin esos datos. La publicación no se puede repetir indefinidamente: el identificador del documento debe ser único y un segundo envío idéntico se rechaza. El catálogo explica cómo probar las variantes sin confundir ese rechazo con otro problema.

### Diferencias con Plataforma que afectan las pruebas

| Tema | En este Gateway | En Plataforma |
| --- | --- | --- |
| Contenido CDA | Se incluye el Binary en el envío para guardarlo y recuperarlo localmente. | El prestador conserva el CDA y proporciona su ubicación. |
| Enlaces al contenido en ITI-65 | Los ejemplos enlazan las entradas mediante `urn:uuid:`. | Se necesitan las URL recuperables del prestador para las representaciones. |
| Ubicaciones de la respuesta ITI-65 | Pueden identificar recursos guardados en HAPI. | No representan ubicaciones reales de recursos FHIR persistentes. |
| Igual CI y distinto MRN | El Gateway rechaza el segundo registro con 412. | Los registros se distinguen por dominio y valor MRN. |

Una referencia `urn:uuid:` identifica una entrada dentro del envío. No es una dirección recuperable mediante el navegador. La recuperación utiliza la URL recibida en ITI-67, como se explica en CA-05.

## 7. Detener y volver a iniciar

```bash
docker compose -f compose/docker-compose.yml down
```

Este comando conserva los datos en los volúmenes. Para continuar después, se ejecuta nuevamente `up -d --wait`. La opción `-v` elimina los volúmenes y sus datos, por lo que debe omitirse para conservar pacientes y documentos.

Después de modificar valores de `.env`, utilizar `up -d --wait` para que Compose aplique los cambios de configuración. Si sólo se modificaron los certificados o `pixm-sources.yaml`, reiniciar el Gateway con `docker compose -f compose/docker-compose.yml restart ihe-gateway`.

## Si algo falla

Cuando una petición falla, el estado HTTP y el cuerpo de la respuesta ayudan a entender la causa. Un `OperationOutcome` es el recurso FHIR que describe el problema; el detalle se encuentra en sus entradas `issue`. Si falla la conexión TLS, puede no existir respuesta HTTP.

| Síntoma | Qué revisar |
| --- | --- |
| Falta `POSTGRES_PASSWORD` | Completar el valor en `compose/.env`. |
| Falta `keytool` | Utilizar un JDK o la alternativa de generación mediante Docker. |
| El servicio no llega a `healthy` | Consultar sus logs. Revisar `.env.mtls`, certificados y memoria disponible. |
| El certificado no corresponde al host | La dirección utilizada debe estar incluida en el SAN del certificado del servidor. |
| El servidor pide un certificado o corta la conexión | Revisar que el cliente presente el certificado y su clave, emitidos por la CA de esta instalación. |
| Error al importar certificados en Windows | Revisar el cliente TLS utilizado y probar la configuración de Postman o WSL. |
| 403 al registrar el paciente | Revisar que el dominio MRN corresponda al certificado autorizado. |
| 412 con otra historia clínica y la misma CI | Es la diferencia por CI descrita arriba. |
| 400 en la búsqueda | Comprobar `patient.identifier` y `status=current`. |
| 406 al recuperar | Indicar `Accept: application/fhir+json` o `Accept: text/xml`. |
| 422 al publicar | Leer el OperationOutcome. Puede ser un documento repetido, un recurso inválido o la ausencia del Binary requerido por la PoC. |
| La URL recibida apunta a un host incorrecto | Revisar `GATEWAY_PUBLIC_BASE_URL` y aplicar la configuración con Compose. |

Para ampliar: [configuración y acceso a HAPI](docs/ANEXOS.md).
