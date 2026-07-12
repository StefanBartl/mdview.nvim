package relay

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"testing"
	"time"
)

func TestGenerateWebTransportCert(t *testing.T) {
	cert, hash, err := GenerateWebTransportCert()
	if err != nil {
		t.Fatalf("cert generation failed: %v", err)
	}
	if len(cert.Certificate) != 1 {
		t.Fatalf("expected a single DER cert, got %d", len(cert.Certificate))
	}
	if _, ok := cert.PrivateKey.(*ecdsa.PrivateKey); !ok {
		t.Fatalf("expected an ECDSA private key (Chromium requires ECDSA)")
	}

	parsed, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		t.Fatalf("cert does not parse: %v", err)
	}
	// Chromium caps serverCertificateHashes certs at 14 days validity.
	validity := parsed.NotAfter.Sub(parsed.NotBefore)
	if validity > 14*24*time.Hour {
		t.Fatalf("validity %v exceeds the 14-day WebTransport cap", validity)
	}
	if parsed.PublicKeyAlgorithm != x509.ECDSA {
		t.Fatalf("expected ECDSA public key, got %v", parsed.PublicKeyAlgorithm)
	}

	// The reported hash must be the SHA-256 of the DER cert (hex).
	want := sha256.Sum256(cert.Certificate[0])
	if hash != hex.EncodeToString(want[:]) {
		t.Fatalf("hash mismatch: got %s", hash)
	}
}
