# Bora — app Flutter ligado ao Supabase

Login, cadastro, mapa, comunidades, publicar viagem, buscar, reservar e cancelar,
tudo gravando num banco de verdade. O `supabase/schema.sql` foi executado e
testado num Postgres 16 antes da entrega (cenário completo com três usuários).

## 1. Criar o banco (10 minutos)

1. supabase.com > New project (região São Paulo). Use um projeto NOVO, não o do app antigo.
2. SQL Editor > New query > cole o conteúdo inteiro de `supabase/schema.sql` > Run.
   Deve terminar com "Success. No rows returned".
3. Authentication > Sign In / Providers > Email: desligue **Confirm email** e salve.
   (É o que permite o "modo dev" do app enquanto o SMS não está configurado.)
4. Settings > API: copie a **Project URL** e a chave **anon public**.

## 2. Ligar o app ao banco

Escolha um:

- **Pelo GitHub (sem instalar nada):** no repositório, Settings > Secrets and variables >
  Actions, crie `SUPABASE_URL` e `SUPABASE_ANON_KEY`. Suba o projeto, abra a aba Actions,
  rode "Gerar APK" e baixe o APK em Artifacts.
- **Pelo computador:** abra `lib/app/env.dart`, cole a URL e a chave nos dois lugares
  marcados com `COLE_AQUI`, e rode:

```bash
flutter create --org br.com.bora --platforms android,ios bora
cd bora
# copie por cima: lib/, assets/ e pubspec.yaml
flutter pub get
flutter run
```

  No Android, acrescente em `android/app/src/main/AndroidManifest.xml`, antes de `<application`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

  No iOS, em `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>O Bora usa sua localização para sugerir o ponto de embarque mais próximo.</string>
```

A chave anon é pública por natureza; quem protege os dados é o RLS. A chave
`service_role` nunca entra no app.

## 3. Roteiro de teste (dois celulares, ou sair e entrar no mesmo)

1. "Entrar com e-mail (modo dev)" > Criar conta de teste `ana@teste.com`. Cadastro como mulher.
2. Perfil > Cadastrar carro. Comunidades > Criar comunidade > abra e copie o código.
3. Início > "Vou dirigir" > Publicar viagem (ex.: Rodoviária de Planaltina -> W3 Sul), só para a comunidade.
4. Saia. Crie `julia@teste.com`, mulher, marcando "viajar só com mulheres".
5. Busque Sobradinho Quadra 8 -> W3 Sul: não aparece nada (a viagem é restrita).
6. Comunidades > Entrar com código. Busque de novo: aparece, com o selo da comunidade.
7. Reserve, veja o código de embarque. Entre como Ana e puxe a aba Viagens: a Júlia está lá.
8. Crie `carlos@teste.com` (homem), com carro e viagem pública no mesmo trecho:
   a Júlia continua sem ver a viagem dele, por causa da preferência.

Dá para conferir tudo no painel: Table Editor > `rides`, `bookings`, `unmet_searches`.

## 4. SMS de verdade (quando quiserem)

Authentication > Sign In / Providers > Phone: habilite e configure um provedor (Twilio etc.).
No mesmo painel, "Test phone numbers" aceita pares `5561999990001=123456` para
entrar sem gastar SMS. O botão "Entrar com meu celular" já usa esse fluxo.
Antes de lançar, remova a tela `dev_login_screen.dart` e o botão da tela inicial.

## 5. O que ainda é simulado ou não existe

- Foto do documento e selfie: tocar no cartão "tira a foto". Não há upload.
- Aprovação de identidade: automática enquanto `app_config.auto_approve_identity = true`.
  Para exigir aprovação manual: `update app_config set auto_approve_identity = false;`
  e aprove com `update profiles set identity_status = 'approved' where id = '...';`
  até existir o painel admin.
- Rotas: menor caminho no grafo de paradas (`stops` + `stop_links`), linhas retas no mapa.
  Para acrescentar paradas, insira em `stops` e ligue em `stop_links`.
- Pagamento: o app mostra o rateio; o acerto é direto com o motorista.
- Tempo real: as telas atualizam ao puxar para baixo, não sozinhas.
- Ainda não feito: viagem ao vivo no mapa, confirmação de embarque pelo motorista,
  link do contato de emergência, SOS, avaliações, histórico, denúncia e bloqueio,
  notificações, exclusão de conta, painel admin.

## Estrutura

```
supabase/schema.sql      banco inteiro: tabelas, regras (funções), RLS e paradas iniciais
lib/
  app/        env (chaves), providers, rotas com redirecionamento por status
  data/       bora_store.dart (estado + TODAS as chamadas ao Supabase), grafo, erros
  domain/     modelos com leitura do JSON que o banco devolve
  core/       tema, widgets (botão, cartões, mapa), validadores, formatadores
  features/   auth, onboarding, home, search, bookings, rides, trips, communities, profile
```

As regras de negócio (vaga, preço, filtros de gênero, audiência por comunidade)
moram nas funções SQL. O app só chama; não dá para burlar mexendo no cliente.
