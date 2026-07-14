#!/usr/bin/env bash
set -euo pipefail

# Neden bu script var?
# -------------------
# Dağıtılan (GitHub Release) build ad-hoc imzalıdır (paid Apple Developer hesabı
# olmadığından). Ad-hoc imzada uygulamanın "kimliği" ikili dosyanın hash'inden
# türer; bu kimlik stabil olmadığından macOS keychain "Always Allow" güvenini
# kalıcı tutamaz ve login/relock/relaunch sonrası tekrar tekrar şifre sorar
# (özellikle Claude Code CLI'nin login Keychain'deki "Claude Code-credentials"
# item'ını okurken — bu item CursorMeterFS'in kendi item'ı değil, cross-app okuma).
#
# Bu script, login Keychain'de KALICI bir self-signed code-signing sertifikası
# oluşturur (yoksa) ve kurulu CursorMeterFS.app'i bu sertifikayla yeniden
# imzalar. Sertifika sabit kaldığı sürece imzalayan kimlik de sabit kalır,
# dolayısıyla verdiğiniz "Always Allow" kararı kalıcı olur.
#
# Admin/sudo GEREKMEZ — her şey kullanıcının kendi login Keychain'i içinde olur.
# Her iki makinede de tek seferlik çalıştırılması yeterlidir; app güncellenince
# tekrar çalıştırmanız gerekir (yeni .app farklı bir dosya, ama AYNI sertifikayla
# imzalanacağı için ACL güveni bozulmaz).

CERT_NAME="CursorMeterFS Local CodeSign"
APP_PATH="${1:-/Applications/CursorMeterFS.app}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "🔐 CursorMeterFS yerel kod imzalama başlıyor..."

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Uygulama bulunamadı: $APP_PATH"
  echo "   Farklı bir konum kullanıyorsanız: bash scripts/sign-local.sh /path/to/CursorMeterFS.app"
  exit 1
fi

# --- 1. Sertifika zaten var mı? -------------------------------------------
if security find-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" &>/dev/null; then
  echo "✅ Sertifika zaten mevcut: $CERT_NAME"
else
  echo "📜 Yeni self-signed code-signing sertifikası oluşturuluyor..."

  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT

  KEY_PEM="$WORKDIR/key.pem"
  CERT_PEM="$WORKDIR/cert.pem"
  P12_PATH="$WORKDIR/cert.p12"
  P12_PASS="$(openssl rand -base64 24)"

  # Code Signing EKU (1.3.6.1.5.5.7.3.3) + digitalSignature key usage şart.
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY_PEM" -out "$CERT_PEM" \
    -days 3650 \
    -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"

  # -legacy: OpenSSL 3.x varsayılan PBES2 şifrelemesi macOS Security framework'ünün
  # eski PKCS12 çözücüsüyle uyumsuz ("MAC verification failed"). Legacy RC2/3DES
  # şifreleme kullanarak `security import`'un okuyabildiği formatı üretiyoruz.
  openssl pkcs12 -export -legacy \
    -out "$P12_PATH" \
    -inkey "$KEY_PEM" -in "$CERT_PEM" \
    -passout "pass:$P12_PASS"

  echo "📥 Sertifika login Keychain'e ekleniyor (codesign kullanımına izin verilecek)..."
  security import "$P12_PATH" -k "$LOGIN_KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -A

  # Trust ayarı: kullanıcı-scope'lu, sadece code-signing amaçlı. Sudo gerekmez
  # çünkü sistem geneli değil, bu kullanıcının login Keychain'i için ekleniyor.
  security add-trusted-cert -r trustAsRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$CERT_PEM" 2>/dev/null || true

  # codesign'ın private key'e prompt'suz erişebilmesi için partition list.
  # Bu adım login Keychain parolanızı bir kez isteyebilir — bu, uygulamanın
  # tekrar eden prompt sorunundan FARKLI, tek seferlik bir kurulum adımıdır.
  security set-key-partition-list -S apple-tool:,apple: -s -k "" "$LOGIN_KEYCHAIN" &>/dev/null || \
    echo "ℹ️  set-key-partition-list atlandı (gerekirse ilk imzalamada parola istenebilir)."

  echo "✅ Sertifika oluşturuldu ve import edildi."
fi

# --- 2. Uygulamayı yeniden imzala -----------------------------------------
echo "✍️  $APP_PATH yeniden imzalanıyor..."
codesign --force --deep --options runtime --sign "$CERT_NAME" "$APP_PATH"
codesign --verify --deep "$APP_PATH"

echo ""
echo "=== Doğrulama ==="
codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Authority|flags|TeamIdentifier" || true

echo ""
echo "✅ Bitti. Şimdi:"
echo "   1) CursorMeterFS'i kapatıp yeniden açın"
echo "   2) İlk Claude sekmesi yenilemesinde çıkan Keychain prompt'unda"
echo "      'Her zaman izin ver' (Always Allow) seçin"
echo "   3) Sertifika sabit kaldığı sürece bir daha sormayacak"
echo ""
echo "⚠️  Uygulamayı güncellediğinizde (yeni .app kopyaladığınızda) bu script'i"
echo "   tekrar çalıştırın — sertifika aynı kalacağı için Keychain güveni korunur."
