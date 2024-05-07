#!/bin/bash -eu

PRJDIR="$(cd "$(dirname "$0")/../";pwd)"

if ! type shdoc >/dev/null 2>&1;then
  echo "Error: shdoc not found."
  echo "Plz Install: https://github.com/reconquest/shdoc"
  exit 1
fi

mkdir -p "$PRJDIR/docs/shelldoc"
while read -r shellfile;do
  p="docs/shelldoc/$(basename "$shellfile").md"
  shdoc < "${shellfile}.sh" > "$PRJDIR/$p"
  echo "* Generated \"$p\""
done < <(find "$PRJDIR/lib" -name "*.sh" | sed 's;\.sh$;;g')

echo ""
echo "# Completed!"

