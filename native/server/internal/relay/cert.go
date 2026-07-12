package relay

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"math/big"
	"time"
)

// GenerateWebTransportCert creates a short-lived, self-signed ECDSA P-256
// certificate for localhost, suitable for a WebTransport connection pinned via
// the browser's serverCertificateHashes option. Chromium requires such a
// certificate to be ECDSA (P-256) with a validity period of at most 14 days;
// this uses ~13 days to stay safely inside that window.
//
// Returns the TLS certificate to serve and the lowercase hex SHA-256 of the DER
// certificate — the value the client passes as serverCertificateHashes so it
// trusts exactly this cert without a public CA.
func GenerateWebTransportCert() (tls.Certificate, string, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, "", err
	}

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return tls.Certificate{}, "", err
	}

	now := time.Now()
	tmpl := x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "mdview-localhost"},
		NotBefore:             now.Add(-1 * time.Hour),
		NotAfter:              now.Add(13 * 24 * time.Hour), // < 14 days (Chromium cap)
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost"},
	}

	der, err := x509.CreateCertificate(rand.Reader, &tmpl, &tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, "", err
	}

	sum := sha256.Sum256(der)
	cert := tls.Certificate{
		Certificate: [][]byte{der},
		PrivateKey:  key,
		Leaf:        &tmpl,
	}
	return cert, hex.EncodeToString(sum[:]), nil
}
