#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${HERE}/../FB Loader/FB LoaderTests/Fixtures"
mkdir -p "${OUT}"
TMP="$(mktemp -d)"
cd "${TMP}"
mkdir -p inpx
# 2 books in archive "lib-001"
printf 'Толстой,Лев,Николаевич\x04prose_classic\x04Война и мир\x04Великие романы\x041\x04100001\x041000\x04100001\x040\x04fb2\x042010-05-15\x04ru\n' > inpx/lib-001.inp
printf 'Дяченко,Марина,:Дяченко,Сергей,:Олди,Генри,Лайон\x04sf_social\x04Рубеж. Пентакль\x04Большая серия\x041\x04200001\x046400838\x04200001\x040\x04fb2\x042013-11-10\x04ru\n' >> inpx/lib-001.inp
echo '20260301' > inpx/version.info
printf 'flibusta FB2 - 2026-03-01\nflibusta_20260301\n65536\nLocal Flibusta library' > inpx/collection.info
( cd inpx && zip -r "${OUT}/tiny.inpx" . )
echo "Fixture written: ${OUT}/tiny.inpx"
