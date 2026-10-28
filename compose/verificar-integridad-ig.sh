#!/bin/sh
# Comprueba la integridad de los paquetes de la PoC HCEN antes del arranque.
# Ver README.md. La integridad no acredita que la versión del paquete sea la vigente.
set -eu

RAIZ=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$RAIZ"

FALLOS=0

verificar_directorio() {
  d="$1"
  sums="$d/SHA256SUMS"
  if [ ! -f "$sums" ]; then
    echo "  >> BLOQUEA: $sums no existe (SEC-29 exige un fichero de hash junto a los .tgz)"
    FALLOS=1
    return
  fi
  for tgz in "$d"/*.tgz; do
    [ -e "$tgz" ] || continue   # sin .tgz en el directorio (glob sin match)
    nombre=$(basename "$tgz")
    # Acepta manifiestos LF y CRLF y compara el nombre de forma literal.
    # sha256sum usa 64 caracteres de hash, un espacio y el modo (* o espacio).
    if ! awk -v nombre="$nombre" '
      { sub(/\r$/, "") }
      substr($0, 65, 1) == " " && substr($0, 66, 1) ~ /^[* ]$/ && substr($0, 67) == nombre { encontrado = 1 }
      END { exit !encontrado }
    ' "$sums"; then
      echo "  >> BLOQUEA: $tgz no tiene entrada en $sums (paquete sin hash registrado)"
      FALLOS=1
    fi
  done
  echo "  -- $d --"
  # Acepta SHA256SUMS con finales de línea CRLF (copia hecha en Windows).
  ( cd "$d" && tr -d '\r' < SHA256SUMS | sha256sum -c - ) || FALLOS=1
}

if [ $# -ge 1 ]; then
  verificar_directorio "$1"
else
  verificar_directorio hapi/packages
  verificar_directorio validator/igs
fi

if [ "$FALLOS" -ne 0 ]; then
  echo
  echo "SEC-29: integridad de .tgz del IG NO verificada. No levantes el stack con estos archivos."
  exit 1
fi
echo
echo "SEC-29: todos los .tgz del IG coinciden con su SHA-256 registrado."
