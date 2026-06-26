#!/usr/bin/env bash
set -euo pipefail

echo "🔧 CursorMeterFS bootstrap başlıyor..."

# xcodegen kur (yoksa)
if ! command -v xcodegen &>/dev/null; then
  echo "📦 xcodegen kuruluyor..."
  brew install xcodegen
else
  echo "✅ xcodegen mevcut: $(xcodegen version)"
fi

# .xcodeproj oluştur
echo "🔨 Xcode projesi üretiliyor..."
xcodegen generate

echo ""
echo "✅ Hazır! Şimdi:"
echo "   open CursorMeterFS.xcodeproj"
echo ""
echo "⚠️  İlk çalıştırmada Xcode -> Signing & Capabilities'te"
echo "   kendi Apple ID'nizi seçin (Personal Team yeterli)."
