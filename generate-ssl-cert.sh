#!/usr/bin/env bash
set -euo pipefail

# Default values
SSL_DIR="${SSL_DIR:-$(pwd)/ssl}"
DAYS=${DAYS:-365}
CN=${CN:-localhost}
SUBJECT=${SUBJECT:-}
CREATE_CA=${CREATE_CA:-true}
FORCE=${FORCE:-false}

usage() {
  cat <<EOF
Usage: $0 [-d ssl_dir] [-n days] [-c common_name] [-s subject] [--no-ca] [-f]
  -d  output directory for certificates (default: ./ssl)
  -n  validity period in days (default: 365)
  -c  common name / hostname (default: localhost)
  -s  full subject string (overrides -c)
  --no-ca  create self-signed cert without CA (simpler but less secure)
  -f  force overwrite existing certificates

Output files:
  ssl/ca.crt          - Certificate Authority (if --no-ca not used)
  ssl/ca.key          - CA private key (keep secure!)
  ssl/cert.pem        - Server certificate
  ssl/cert.key        - Server private key

Examples:
  $0                          # Generate certs for localhost
  $0 -c myhost.local          # Generate certs for custom hostname
  $0 -c "*.local" -n 730      # Wildcard cert, 2 years validity
  $0 --no-ca                  # Simple self-signed (no CA)
  $0 -f                       # Force overwrite existing certs
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) SSL_DIR="$2"; shift 2 ;;
    -n) DAYS="$2"; shift 2 ;;
    -c) CN="$2"; shift 2 ;;
    -s) SUBJECT="$2"; shift 2 ;;
    --no-ca) CREATE_CA=false; shift ;;
    -f) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Check if certificates already exist
if [[ -f "${SSL_DIR}/cert.pem" && "${FORCE}" != "true" ]]; then
  echo "Certificate already exists at ${SSL_DIR}/cert.pem"
  echo "Use -f to force overwrite."
  exit 1
fi

# Create SSL directory
mkdir -p "${SSL_DIR}"

# Build subject string
if [[ -z "${SUBJECT}" ]]; then
  SUBJECT="/C=US/ST=State/L=City/O=Development/CN=${CN}"
fi

echo "Generating SSL certificates..."
echo "  Output: ${SSL_DIR}/"
echo "  Common Name: ${CN}"
echo "  Validity: ${DAYS} days"
echo ""

if [[ "${CREATE_CA}" == "true" ]]; then
  # Method 1: Create CA + signed certificate (recommended)
  echo "Creating Certificate Authority..."
  
  # Generate CA private key
  openssl genrsa -out "${SSL_DIR}/ca.key" 4096 2>/dev/null
  
  # Generate CA certificate
  openssl req -new -x509 -days "${DAYS}" \
    -key "${SSL_DIR}/ca.key" \
    -out "${SSL_DIR}/ca.crt" \
    -subj "/C=US/ST=State/L=City/O=Development CA/CN=Local Development CA" \
    2>/dev/null
  
  echo "Creating server certificate signed by CA..."
  
  # Generate server private key
  openssl genrsa -out "${SSL_DIR}/cert.key" 2048 2>/dev/null
  
  # Generate certificate signing request
  openssl req -new \
    -key "${SSL_DIR}/cert.key" \
    -out "${SSL_DIR}/cert.csr" \
    -subj "${SUBJECT}" \
    2>/dev/null
  
  # Create extensions file for SAN (Subject Alternative Names)
  cat > "${SSL_DIR}/cert.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CN}
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
  
  # Sign server certificate with CA
  openssl x509 -req -days "${DAYS}" \
    -in "${SSL_DIR}/cert.csr" \
    -CA "${SSL_DIR}/ca.crt" \
    -CAkey "${SSL_DIR}/ca.key" \
    -CAcreateserial \
    -out "${SSL_DIR}/cert.pem" \
    -extfile "${SSL_DIR}/cert.ext" \
    2>/dev/null
  
  # Cleanup temporary files
  rm -f "${SSL_DIR}/cert.csr" "${SSL_DIR}/cert.ext" "${SSL_DIR}/ca.srl"
  
  # Set permissions
  chmod 600 "${SSL_DIR}/ca.key" "${SSL_DIR}/cert.key"
  chmod 644 "${SSL_DIR}/ca.crt" "${SSL_DIR}/cert.pem"
  
  echo ""
  echo "=== Certificate Authority Created ==="
  echo "  CA Certificate: ${SSL_DIR}/ca.crt"
  echo "  CA Private Key: ${SSL_DIR}/ca.key (keep secure!)"
  echo ""
  echo "=== Server Certificate Created ==="
  echo "  Certificate: ${SSL_DIR}/cert.pem"
  echo "  Private Key: ${SSL_DIR}/cert.key"
  echo ""
  echo "=== Next Steps ==="
  echo "1. Trust the CA certificate on your system:"
  echo ""
  echo "   macOS:"
  echo "     sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${SSL_DIR}/ca.crt"
  echo ""
  echo "   Linux (Ubuntu/Debian):"
  echo "     sudo cp ${SSL_DIR}/ca.crt /usr/local/share/ca-certificates/local-dev-ca.crt"
  echo "     sudo update-ca-certificates"
  echo ""
  echo "   Chrome/Chromium (manual):"
  echo "     Settings → Privacy and security → Security → Manage certificates"
  echo "     → Authorities → Import → Select ${SSL_DIR}/ca.crt"
  echo ""
  echo "2. Start the container (SSL auto-detected from ./ssl/):"
  echo "     ./start-container.sh --encoder nvidia --gpu all"
  echo ""
  
else
  # Method 2: Simple self-signed certificate (no CA)
  echo "Creating self-signed certificate (no CA)..."
  
  openssl req -x509 -nodes -days "${DAYS}" -newkey rsa:2048 \
    -keyout "${SSL_DIR}/cert.key" \
    -out "${SSL_DIR}/cert.pem" \
    -subj "${SUBJECT}" \
    -addext "subjectAltName=DNS:${CN},DNS:localhost,IP:127.0.0.1" \
    2>/dev/null
  
  chmod 600 "${SSL_DIR}/cert.key"
  chmod 644 "${SSL_DIR}/cert.pem"
  
  echo ""
  echo "=== Self-Signed Certificate Created ==="
  echo "  Certificate: ${SSL_DIR}/cert.pem"
  echo "  Private Key: ${SSL_DIR}/cert.key"
  echo ""
  echo "Note: Browsers will show security warnings for self-signed certificates."
  echo "Use without --no-ca to create a CA that can be trusted system-wide."
  echo ""
fi

echo "Done!"
