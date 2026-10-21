#!/bin/zsh
# Gera as imagens de exemplo em docs/images a partir das views reais do widget (dados fictícios).
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
sed -e 's/^@main//' -e 's/@Environment(\\.widgetFamily) var family/var family: WidgetFamily = .systemSmall/' \
  Widget/UsageWidget.swift > "$TMP/W.swift"
swiftc -parse-as-library -o "$TMP/render" Shared/UsageData.swift "$TMP/W.swift" scripts/RenderPreviews.swift
"$TMP/render"
