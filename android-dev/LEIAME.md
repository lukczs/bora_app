# Chave de assinatura dos APKs de teste

`bora-dev.keystore` assina os APKs gerados pelo GitHub Actions. Ela é fixa para:

- o Android aceitar atualizar o app sem desinstalar;
- a chave do Google Maps poder ser travada neste app.

Senha `android`, alias `androiddebugkey` (padrão de chave de desenvolvimento).
SHA-1: `8D:B6:F3:16:B2:4D:69:9F:AC:D9:7E:B1:2E:6A:61:16:AC:8C:E3:0B`

**Não use esta chave para publicar na Play Store.** Para a loja, crie uma chave de
upload própria e guarde fora do repositório.
