# Vault

## Bootstrapping

```
sudo groupadd --system vault
sudo useradd --system \
  --home /etc/vault.d \
  --shell /bin/false \
  --gid vault \
  vault
sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /opt/vault
sudo chmod -R 750 /opt/vault
```

## Unsealing

For now, we are using [vault-unseal](https://github.com/lrstanley/vault-unseal). It's not perfect, but it works for now.
