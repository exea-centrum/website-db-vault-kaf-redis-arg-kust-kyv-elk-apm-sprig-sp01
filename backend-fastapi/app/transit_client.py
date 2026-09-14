#!/usr/bin/env python3
"""
KROK 6 (Transit): Vault Transit Engine client dla aplikacji Python.
Szyfruje/deszyfruje wrażliwe dane (PII, telefony, e-maile) przed zapisem do bazy.

Użycie:
    from transit_client import TransitClient, encrypt, decrypt
    
    # Szyfrowanie
    ciphertext = encrypt("Jan Kowalski, +48 123 456 789")
    
    # Deszyfrowanie
    plaintext = decrypt(ciphertext)
"""

import os
import base64
import logging
import requests
from typing import Optional, Dict

logger = logging.getLogger(__name__)


class VaultTokenProvider:
    """Pobiera token Vault przez Kubernetes auth."""
    
    def __init__(self):
        self.vault_addr = os.environ.get(
            "VAULT_TRANSIT_ADDR", 
            "http://vault.davtro02.svc.cluster.local:8200"
        )
        self.auth_role = os.environ.get(
            "VAULT_TRANSIT_AUTH_ROLE", 
            "davtro-transit"
        )
        self._token = None
    
    def get_token(self) -> str:
        """Pobiera token przez Kubernetes auth."""
        if self._token:
            return self._token
        
        sa_token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        with open(sa_token_path, "r") as f:
            sa_token = f.read().strip()
        
        url = f"{self.vault_addr}/v1/auth/kubernetes/login"
        payload = {"jwt": sa_token, "role": self.auth_role}
        
        try:
            resp = requests.post(url, json=payload, timeout=10)
            resp.raise_for_status()
            self._token = resp.json()["auth"]["client_token"]
            return self._token
        except Exception as e:
            logger.error(f"Vault auth failed: {e}")
            raise


class TransitClient:
    """Client dla Vault Transit Engine."""
    
    def __init__(self, key_name: Optional[str] = None):
        self.vault_addr = os.environ.get(
            "VAULT_TRANSIT_ADDR", 
            "http://vault.davtro02.svc.cluster.local:8200"
        )
        self.key_name = key_name or os.environ.get("VAULT_TRANSIT_KEY", "davtro-app")
        self.token_provider = VaultTokenProvider()
        self._session = requests.Session()
    
    def _get_headers(self) -> Dict[str, str]:
        """Zwraca headers z tokenem."""
        token = self.token_provider.get_token()
        return {"X-Vault-Token": token}
    
    def encrypt(self, plaintext: str) -> str:
        """Szyfruje dane przez Vault Transit Engine."""
        b64_plaintext = base64.b64encode(plaintext.encode()).decode()
        url = f"{self.vault_addr}/v1/transit/encrypt/{self.key_name}"
        payload = {"plaintext": b64_plaintext}
        
        resp = self._session.post(
            url, json=payload, headers=self._get_headers(), timeout=30
        )
        resp.raise_for_status()
        return resp.json()["data"]["ciphertext"]
    
    def decrypt(self, ciphertext: str) -> str:
        """Deszyfruje dane z Vault Transit Engine."""
        url = f"{self.vault_addr}/v1/transit/decrypt/{self.key_name}"
        payload = {"ciphertext": ciphertext}
        
        resp = self._session.post(
            url, json=payload, headers=self._get_headers(), timeout=30
        )
        resp.raise_for_status()
        
        b64_plaintext = resp.json()["data"]["plaintext"]
        return base64.b64decode(b64_plaintext).decode()
    
    def encrypt_dict(self, data: Dict[str, str]) -> Dict[str, str]:
        """Szyfruje wartości w słowniku."""
        return {k: self.encrypt(v) for k, v in data.items()}
    
    def decrypt_dict(self, data: Dict[str, str]) -> Dict[str, str]:
        """Deszyfruje wartości w słowniku."""
        return {k: self.decrypt(v) for k, v in data.items()}


# Globalna instancja (lazy init)
_transit_client: Optional[TransitClient] = None


def get_transit_client() -> TransitClient:
    """Zwraca globalną instancję TransitClient."""
    global _transit_client
    if _transit_client is None:
        _transit_client = TransitClient()
    return _transit_client


# Helper functions dla wygodnego użycia
def encrypt(plaintext: str) -> str:
    """Szyfruje dane przez Vault Transit Engine."""
    return get_transit_client().encrypt(plaintext)


def decrypt(ciphertext: str) -> str:
    """Deszyfruje dane z Vault Transit Engine."""
    return get_transit_client().decrypt(ciphertext)
