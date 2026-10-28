# Gateway HCEN 1.0.0 — notas de la versión

La 1.0.0 es la versión inicial del Gateway HCEN, entregada por desarrollo el 28 de octubre de 2026. Estas notas resumen los componentes de la distribución y los servicios que ofrece. La primera instalación se describe en el [tutorial](README.md).

La versión del Gateway es independiente de la versión del paquete de la guía que utiliza su validador.

## Componentes de la distribución

| Componente | Versión |
| --- | --- |
| Gateway | 1.0.0 |
| Validador | 1.1.1 |
| Proxy del validador | 0.1.0 |
| HAPI FHIR | v8.12.0-1 |
| PostgreSQL | 16-alpine |

Las imágenes están fijadas por digest en Compose y su configuración. La actualización local del paquete de la guía no cambia las imágenes anteriores.

## Servicios incluidos

El Gateway es la única base FHIR pública de la instalación (`/fhir`). Recibe las peticiones, aplica los controles del intercambio, valida los recursos contra la guía y guarda los datos en HAPI FHIR. Las direcciones que devuelve apuntan siempre al Gateway.

### Registro de pacientes — ITI-104

Comunica la identificación y los datos del paciente del prestador. El paciente se registra o actualiza con `PUT /fhir/Patient?identifier=<dominio>|<MRN>`. Cada dominio MRN está autorizado para un único sistema cliente, identificado por su certificado.

### Publicación de documentos — ITI-65

Envía el documento clínico y los metadatos que permiten encontrarlo, en un Bundle de transacción a `/fhir`. Se registra un único DocumentReference por documento. El envío incluye el Binary con el CDA, que el Gateway guarda para poder recuperarlo localmente. Si el paciente todavía no existe, se crea en la misma transacción (`MHD_PATIENT_CREATE_ENABLED`, activada en esta distribución).

### Búsqueda de documentos — ITI-67

Consulta los metadatos de los documentos de un paciente en `/fhir/DocumentReference`. Cada resultado indica en `content.attachment.url` la dirección completa para recuperar el contenido.

### Recuperación de documentos — ITI-68

Descarga el contenido con GET sobre la URL recibida en ITI-67. La cabecera Accept elige la representación: `application/fhir+json` para el documento FHIR y `text/xml` para el CDA. Sin Accept, o con un valor no admitido, la petición se rechaza.
