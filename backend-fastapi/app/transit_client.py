#!/usr/bin/env python3
"""
KROK 4 (Transit PII): Vault Transit Engine client dla aplikacji Python.
Szyfruje/deszyfruje wrazliwe dane (PII, telefony, e-maile) przed zapisem do bazy.

Vault zarzadza kluczem KEK (transit/keys/davtro-app, auto-rotate 30 dni),
aplikacja nie widzi klucza - wysyla plaintext do Vaulta i dostaje ciphertext
("vault:v1:..."). Token do Vaulta pobierany przez Kubernetes auth
(role davtro-transit, SA davtro-sa, ttl 1h) i odswiezany po wygasnieciu.

Uzycie:
    from .transit_client import encrypt, decrypt

    ciphertext = encrypt("Jan Kowalski, +48 123 456 789")
    plaintext = decrypt(ciphertext)
"""

import base64
import logging
import os
import time
from typing import Dict, Optional

import requests

logger = logging.getLogger(__name__)

# Token z K8s auth ma ttl=1h - odswiezamy z zapasem, zeby nie trafic na 403.
TOKEN_TTL_SECONDS = 3000


class VaultTokenProvider:
    """Pobiera token Vault przez Kubernetes auth (z cache i auto-renew)."""

    def __init__(self):
        self.vault_addr = os.environ.get(
            "VAULT_TRANSIT_ADDR",
            "http://vault.davtro02.svc.cluster.local:8200",
        )
        self.auth_role = os.environ.get(
            "VAULT_TRANSIT_AUTH_ROLE",
            "davtro-transit",
        )
        self._token: Optional[str] = None
        self._token_expiry: float = 0.0

    def get_token(self, renew: bool = False) -> str:
        """Zwraca wazny token Vault; renew=True wymusza ponowny login."""
        if self._token and not renew and time.time() < self._token_expiry:
            return self._token

        sa_token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        with open(sa_token_path, "r") as f:
            sa_token = f.read().strip()

        url = f"{self.vault_addr}/v1/auth/kubernetes/login"
        payload = {"jwt": sa_token, "role": self.auth_role}

        resp = requests.post(url, json=payload, timeout=10)
        resp.raise_for_status()
        auth = resp.json()["auth"]
        self._token = auth["client_token"]
        lease = int(auth.get("lease_duration") or 3600)
        # Odswiezamy minute przed wygasnieciem, ale nie pozniej niz TOKEN_TTL_SECONDS.
        self._token_expiry = time.time() + max(60, min(lease - 60, TOKEN_TTL_SECONDS))
        return self._token


class TransitClient:
    """Client dla Vault Transit Engine."""

    def __init__(self, key_name: Optional[str] = None):
        self.vault_addr = os.environ.get(
            "VAULT_TRANSIT_ADDR",
            "http://vault.davtro02.svc.cluster.local:8200",
        )
        self.key_name = key_name or os.environ.get("VAULT_TRANSIT_KEY", "davtro-app")
        self.token_provider = VaultTokenProvider()
        self._session = requests.Session()

    def _request(self, path: str, payload: Dict[str, str]) -> Dict:
        """POST do Vaulta z auto-renew tokena przy 403 (token wygasl)."""
        url = f"{self.vault_addr}/v1/{path}"
        for attempt in (1, 2):
            try:
                token = self.token_provider.get_token(renew=(attempt == 2))
            except Exception as exc:
                logger.error("Vault auth failed: %s", exc)
                raise
            resp = self._session.post(
                url, json=payload, headers={"X-Vault-Token": token}, timeout=30
            )
            if resp.status_code == 403 and attempt == 1:
                logger.warning("Vault 403 - odswiezam token i ponawiam")
                continue
            resp.raise_for_status()
            return resp.json()["data"]
        raise RuntimeError("Vault transit: nieudana autoryzacja po renew tokena")

    def encrypt(self, plaintext: str) -> str:
        """Szyfruje dane przez Vault Transit Engine."""
        b64_plaintext = base64.b64encode(str(plaintext).encode()).decode()
        data = self._request(
            f"transit/encrypt/{self.key_name}", {"plaintext": b64_plaintext}
        )
        return data["ciphertext"]

    def decrypt(self, ciphertext: str) -> str:
        """Deszyfruje dane z Vault Transit Engine."""
        data = self._request(
            f"transit/decrypt/{self.key_name}", {"ciphertext": ciphertext}
        )
        return base64.b64decode(data["plaintext"]).decode()

    def encrypt_dict(self, data: Dict[str, str]) -> Dict[str, str]:
        """Szyfruje wartosci w slowniku."""
        return {k: self.encrypt(v) for k, v in data.items()}

    def decrypt_dict(self, data: Dict[str, str]) -> Dict[str, str]:
        """Deszyfruje wartosci w slowniku."""
        return {k: self.decrypt(v) for k, v in data.items()}


# Globalna instancja (lazy init)
_transit_client: Optional[TransitClient] = None


def get_transit_client() -> TransitClient:
    """Zwraca globalna instancje TransitClient."""
    global _transit_client
    if _transit_client is None:
        _transit_client = TransitClient()
    return _transit_client


# Helper functions dla wygodnego uzycia
def encrypt(plaintext: str) -> str:
    """Szyfruje dane przez Vault Transit Engine."""
    return get_transit_client().encrypt(plaintext)


def decrypt(ciphertext: str) -> str:
    """Deszyfruje dane z Vault Transit Engine."""
    return get_transit_client().decrypt(ciphertext)
