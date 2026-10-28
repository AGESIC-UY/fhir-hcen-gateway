# Casos de prueba del Gateway HCEN

Estos casos permiten recorrer el intercambio con los ejemplos incluidos. La numeración CA-XX pertenece a este tutorial HCEN y no conserva la equivalencia con los casos del catálogo anterior.

Antes de comenzar se requiere completar la instalación y la configuración de curl o Postman del [tutorial](../README.md). Los comandos se ejecutan desde la raíz del paquete y utilizan las variables Bash `BASE` y `CLIENTE` definidas allí.

| Caso | Objetivo | Cuándo ejecutarlo |
| --- | --- | --- |
| CA-01 | Comprobar conexión y certificado | Primero. |
| CA-02 | Registrar al paciente | Después de CA-01. |
| CA-03 | Publicar el documento | Después de CA-02. |
| CA-04 | Buscar el documento | Después de CA-03. |
| CA-05 | Recuperar FHIR y CDA | Con la URL obtenida en CA-04. |
| CA-06 | Actualizar al paciente | Variante, después del recorrido principal. |
| CA-07 | Publicar sin registro previo | Variante en una instalación sin los datos del ejemplo. |
| CA-08 | Comprobar el rechazo de un documento repetido | Después de una publicación exitosa. |
| CA-09 | Comprobar el requisito de Accept | Con una URL recuperable obtenida en CA-04. |

## Archivos que se envían

| Archivo | Contenido |
| --- | --- |
| [paciente.json](../set-pruebas/paciente.json) | Patient para el registro inicial. |
| [paciente-actualizado.json](../set-pruebas/paciente-actualizado.json) | El mismo paciente con otro teléfono. |
| [publicacion.json](../set-pruebas/publicacion.json) | Bundle de publicación de una consulta de medicina general, con FHIR y Binary CDA. |
| [procedencia.json](../set-pruebas/procedencia.json) | Origen y adaptaciones de los ejemplos. Es información de referencia, no una petición. |

Los ejemplos proceden de la guía HCEN. Para la PoC se ajustaron el dominio MRN y los enlaces al contenido, y se agregó un CDA nivel 1 de la misma consulta. En ITI-104 se omite el id estático del ejemplo para que el servidor asigne el identificador local. La identidad del paciente sigue dada por el par MRN.

## CA-01 — Comprobar la conexión

**Objetivo.** Confirmar que el cliente llega al Gateway y presenta su certificado.

**Preparación.** Servicios saludables y cliente configurado según el README.

**Solicitud.** GET a `/metadata`, sin cuerpo y con `Accept: application/fhir+json`.

```bash
"${CLIENTE[@]}" -i -H 'Accept: application/fhir+json' "$BASE/metadata"
```

**Resultado esperado.** HTTP 200 y un recurso `CapabilityStatement`. Este recurso describe capacidades del servidor. Para las pruebas HCEN, se debe seguir el recorrido de este catálogo, sin asumir que toda capacidad anunciada forma parte del contrato de Plataforma.

**Siguiente paso.** Con una respuesta correcta se puede continuar con CA-02. Si la conexión falla antes de devolver un estado HTTP, se deben revisar los certificados.

## CA-02 — Registrar al paciente (ITI-104)

**Objetivo.** Crear el registro del paciente en el dominio del prestador.

**Preparación.** CA-01 completo y paciente del ejemplo todavía no registrado. El dominio MRN está autorizado para `cliente-hcen`.

**Solicitud.** PUT condicional a `Patient?identifier=system|value`. El filtro y el identificador MRN del cuerpo deben coincidir. `%7C` es el carácter `|` codificado en la URL.

```bash
"${CLIENTE[@]}" -i -X PUT \
  "$BASE/Patient?identifier=urn%3Aoid%3A2.16.858.2.99999999.72768.1%7C1873455" \
  -H 'Content-Type: application/fhir+json' -H 'Accept: application/fhir+json' \
  --data-binary @set-pruebas/paciente.json
```

**Resultado esperado.** HTTP 201 en el alta inicial. Si el registro ya existe, el mismo PUT lo sustituye y puede responder 200. Por eso repetirlo no demuestra una segunda alta. La cabecera `Location` identifica el recurso local del Gateway.

**Siguiente paso.** Continuar con CA-03. El archivo de publicación ya contiene el contexto necesario, por lo que no es necesario reemplazar sus referencias con el id recibido.

## CA-03 — Publicar el documento (ITI-65)

**Objetivo.** Publicar la consulta y los metadatos necesarios para encontrarla.

**Preparación.** CA-02 completo. El documento del ejemplo todavía no debe estar publicado.

**Solicitud.** POST a la base FHIR con `publicacion.json` como cuerpo.

```bash
"${CLIENTE[@]}" -i -X POST "$BASE" \
  -H 'Content-Type: application/fhir+json' -H 'Accept: application/fhir+json' \
  --data-binary @set-pruebas/publicacion.json
```

**Resultado esperado.** HTTP 200 y un Bundle `transaction-response`, con una respuesta por cada entrada exterior del envío. El documento clínico anidado cuenta como una entrada. Revisar los estados de las entradas, además del estado HTTP general.

La publicación utiliza al paciente existente sin actualizarlo. El Binary incluido permite que el Gateway almacene el CDA para la recuperación local. Los enlaces `urn:uuid:` conectan las entradas del mismo envío.

**Siguiente paso.** Continuar con CA-04. No es necesario reenviar el documento para comprobar la búsqueda: su `masterIdentifier` debe ser único y el reenvío se rechaza.

## CA-04 — Buscar el documento (ITI-67)

**Objetivo.** Encontrar los metadatos del documento publicado para el paciente.

**Preparación.** CA-03 completo.

**Solicitud.** POST a `/DocumentReference/_search`. El cuerpo es un formulario `x-www-form-urlencoded` con dos campos, no JSON.

```bash
"${CLIENTE[@]}" -i -X POST "$BASE/DocumentReference/_search" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/fhir+json' \
  --data-urlencode 'patient.identifier=urn:oid:2.16.858.2.99999999.72768.1|1873455' \
  --data-urlencode 'status=current'
```

**Resultado esperado.** HTTP 200 y resultados de búsqueda que incluyen el DocumentReference del ejemplo. Una búsqueda válida puede estar vacía si no hay documentos para ese paciente.

**Siguiente paso.** Buscar el documento por su `masterIdentifier` y copiar la URL completa de `content.attachment.url`. Esa dirección se utiliza en CA-05. La URL no debe construirse a partir de un id interno.

## CA-05 — Recuperar FHIR y CDA (ITI-68)

**Objetivo.** Descargar las dos representaciones del documento.

**Preparación.** CA-04 completo. Reemplazar el texto de `DOCUMENTO` por la URL recibida, conservando todos sus parámetros.

```bash
DOCUMENTO='URL-completa-recibida-en-CA-04'
"${CLIENTE[@]}" -H 'Accept: application/fhir+json' \
  -D respuesta-fhir.headers "$DOCUMENTO" -o documento.json
"${CLIENTE[@]}" -H 'Accept: text/xml' \
  -D respuesta-cda.headers "$DOCUMENTO" -o documento.xml
```

**Resultado esperado.** HTTP 200 en las cabeceras guardadas. `documento.json` contiene el Bundle documental FHIR y `documento.xml` contiene el CDA directamente. En Postman se envían dos GET a la misma URL cambiando la cabecera `Accept`.

Comprobar el estado antes de interpretar el archivo como documento: el archivo también puede contener una respuesta de error. `Accept` elige la representación de la respuesta. `Content-Type` describe el cuerpo que se envía y no cumple esa función.

## CA-06 — Actualizar los datos del paciente (ITI-104)

**Objetivo.** Sustituir el registro por el estado completo actualizado del Patient.

**Preparación.** Paciente de CA-02 registrado. El archivo actualizado cambia el teléfono.

```bash
"${CLIENTE[@]}" -i -X PUT \
  "$BASE/Patient?identifier=urn%3Aoid%3A2.16.858.2.99999999.72768.1%7C1873455" \
  -H 'Content-Type: application/fhir+json' -H 'Accept: application/fhir+json' \
  --data-binary @set-pruebas/paciente-actualizado.json
```

**Resultado esperado.** HTTP 200. El MRN conserva la identidad del registro y se sustituye su contenido. Para inspeccionar el teléfono almacenado en la PoC, se puede utilizar la consulta local de Patient del [anexo HAPI](ANEXOS.md#consultar-los-datos-locales).

Actualizar Patient no modifica retrospectivamente el documento clínico ya publicado.

## CA-07 — Publicar sin registrar antes al paciente

**Objetivo.** Comprobar que ITI-65 crea al paciente que no existe.

**Preparación.** Una instalación de prueba que todavía no contenga al paciente ni al documento del ejemplo. Este caso es una alternativa al recorrido CA-02 → CA-03, no un paso que pueda ejecutarse después con los mismos datos.

Realizar CA-01 y luego la petición de CA-03, omitiendo CA-02. No hace falta otro archivo JSON.

**Resultado esperado.** HTTP 200 en la publicación. CA-04 y CA-05 deben permitir buscar y recuperar el documento. La consulta de Patient del anexo permite comprobar la creación local del paciente.

Si el recorrido principal ya fue ejecutado, se requiere otra instalación vacía o un juego de datos sintéticos nuevo y coherente. Cambiar sólo el masterIdentifier no crea un ejemplo nuevo correcto: las identidades y referencias del documento FHIR, sus metadatos y el CDA deben seguir correspondiendo.

## CA-08 — Rechazar una publicación repetida

**Objetivo.** Comprobar la unicidad del identificador del documento.

**Preparación.** CA-03 o CA-07 completado correctamente.

Repetir exactamente la solicitud de CA-03 con el mismo archivo.

**Resultado esperado en el Gateway.** HTTP 422 con un OperationOutcome. El documento no se publica una segunda vez. Leer el diagnóstico para confirmar que el rechazo corresponde al duplicado.

## CA-09 — Recuperación sin Accept

**Objetivo.** Comprobar que el cliente debe elegir la representación.

**Preparación.** Una URL válida en `DOCUMENTO`, obtenida en CA-04.

```bash
"${CLIENTE[@]}" -i -H 'Accept:' "$DOCUMENTO"
```

**Resultado esperado en el Gateway.** HTTP 406. La opción `-H 'Accept:'` elimina la cabecera: simplemente omitir `-H` en curl suele enviar `Accept: */*`.

## Sobre los resultados y los ejemplos

Los estados HTTP indicados describen este Gateway. Las diferencias con Plataforma están explicadas en el README. Un resultado correcto en estos casos no acredita todas las reglas de la guía ni validación terminológica completa.

`procedencia.json` registra los nombres y hashes de los ejemplos de origen de la guía de implementación, junto con las adaptaciones realizadas para la PoC. Los archivos incluidos están preparados para ejecutar los casos; no se necesita disponer de los fuentes ni de las herramientas de generación de la guía.
