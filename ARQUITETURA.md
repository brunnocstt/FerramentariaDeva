# Ferramentaria Deva — Arquitetura do Sistema

> **Versão:** 1.0 — 07/08/2026
> **Autor:** Albus Data
> **URL de produção:** https://ferramentariadeva.albusdata.com.br (pendente configuração de DNS — ver seção 12)

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Stack Tecnológica](#2-stack-tecnológica)
3. [Diagrama Lógico](#3-diagrama-lógico)
4. [Frontend](#4-frontend)
5. [Banco de Dados](#5-banco-de-dados)
6. [Perfis de Usuário e Permissões](#6-perfis-de-usuário-e-permissões)
7. [Máquina de Estados das Ferramentas](#7-máquina-de-estados-das-ferramentas)
8. [Edge Functions (API)](#8-edge-functions-api)
9. [Auditorias](#9-auditorias)
10. [Modelo de Segurança](#10-modelo-de-segurança)
11. [Automação de Alertas](#11-automação-de-alertas)
12. [Deploy e Infraestrutura](#12-deploy-e-infraestrutura)
13. [Pendências Manuais](#13-pendências-manuais)

---

## 1. Visão Geral

O **Ferramentaria Deva** é um sistema de controle de ferramental para a equipe de oficina da Deva, cobrindo todas as filiais (~20 usuários). Resolve o problema de rastreabilidade das ferramentas: identificação, localização (filial), quem está com cada uma, status de aferição (calibração) e histórico de conserto/extravio, além de permitir auditorias periódicas para cercar perdas.

Segue a **mesma arquitetura** do sistema irmão "Deva · Gestão de Projetos": monolito de arquivo único (`index.html`) hospedado no GitHub Pages, com todo o backend delegado ao **Supabase** (projeto isolado, próprio deste app). Mesmo menu lateral, mesma paleta de cores, mesma logo — app diferente, mesma identidade visual da empresa.

**Decisão de design central:** como o público é operacional e historicamente tem mais dificuldade com tecnologia, os campos de estado da ferramenta (`status`, `colaborador_atual_id`, datas de aferição) **não são editáveis diretamente**. Toda mudança de estado passa por um INSERT estruturado na tabela `movimentacoes` (retirar, devolver, enviar/retornar de aferição, enviar/retornar de conserto, reportar extravio, dar baixa), validado por um trigger que só permite transições válidas — e é esse mesmo trigger (não o cliente) que efetivamente atualiza a ferramenta. Isso elimina uma classe inteira de erros de digitação/clique que um formulário livre permitiria.

---

## 2. Stack Tecnológica

| Camada | Tecnologia | Observação |
|---|---|---|
| **Frontend** | React (via Babel standalone) | 18 — sem build step |
| **Estilo** | Tailwind CSS | CDN (JIT) |
| **Ícones** | Lucide React | CDN (esm.sh) |
| **Exportação** | SheetJS (xlsx) | CDN (unpkg) |
| **Autenticação** | Supabase Auth | Email + senha + Turnstile |
| **Banco de dados** | PostgreSQL (Supabase) | Projeto `zdwkdfsqxkcrnkovdvba` ("FerramentariaDeva") |
| **API serverless** | Supabase Edge Functions | Deno runtime |
| **E-mail** | iCloud SMTP via nodemailer | Deno edge function |
| **Hospedagem** | GitHub Pages | `brunnocstt/FerramentariaDeva`, branch `main` |
| **Domínio** | albusdata.com.br | CNAME → GitHub Pages (pendente DNS) |

---

## 3. Diagrama Lógico

```
┌─────────────────────────────────────────────────────────┐
│                    USUÁRIO (navegador)                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │   index.html  (React SPA — GitHub Pages)        │   │
│  │  • Login+Captcha  • Ferramentas  • Movimentações│   │
│  │  • Manutenções    • Auditorias  • Usuários      │   │
│  │  • Relatórios     • Configurações               │   │
│  └────────────────────┬────────────────────────────┘   │
└───────────────────────│─────────────────────────────────┘
                        │ HTTPS (supabase-js SDK)
           ┌────────────▼───────────────────────────┐
           │           SUPABASE                     │
           │  ┌──────────────┐  ┌────────────────┐  │
           │  │  Auth (JWT)  │  │  PostgreSQL DB │  │
           │  └──────────────┘  │  (RLS + Trig.) │  │
           │                    └───────┬────────┘  │
           │  ┌────────────────────────▼──────────┐ │
           │  │         Edge Functions (Deno)     │ │
           │  │  send-email · admin-create-user   │ │
           │  │  admin-update-user · admin-delete │ │
           │  └──────────────────────┬────────────┘ │
           │  pg_cron (diário, 07h BRT) ──┘          │
           └─────────────────────────│──────────────┘
                                     │ SMTP TLS
                            ┌────────▼────────┐
                            │  iCloud Mail    │
                            └─────────────────┘
```

---

## 4. Frontend

Arquivo único `index.html` (~50 KB), sem build step — Babel standalone transpila JSX no navegador.

```
index.html
├── <style>          Tailwind CDN + animações globais
├── <script>         Error boundary global
└── <script type="text/babel" data-type="module">
    ├── Imports       React, Supabase, Lucide, XLSX
    ├── Constantes    SUPA_URL, SUPA_ANON, BLUE, STATUS_FERRAMENTA_INFO, TIPO_MOV_LABEL
    ├── Primitivos    Field, Modal, BtnPrimary/Secondary, ErrorBox, EmptyState, StatCard, StatusBadge
    ├── Auth          LoginScreen (Turnstile), ResetPasswordScreen
    ├── Shell         Sidebar (idêntica ao app de Gestão de Projetos), UserFooterMenu, NotificationPanel
    └── Views         DashboardView, FerramentasView, MovimentacoesView, ManutencoesView,
                       AuditoriasView/AuditoriaExecucaoView, GestaoUsuariosView, RelatoriosView,
                       ConfiguracoesView
```

Reset de senha usa o mesmo padrão definitivo do app de referência: token customizado de 64 caracteres via `?reset_token=`, capturado **antes** de qualquer código Supabase rodar, independente do fluxo nativo `PASSWORD_RECOVERY` (incompatível com SPA sem build). Não existe `reset-password.html` separado neste app — o fluxo native de recovery link não é usado, só o token customizado.

---

## 5. Banco de Dados

### Tabelas

| Tabela | Descrição | RLS |
|---|---|---|
| `filiais` | As 6 filiais com oficina (Betim, Juiz de Fora, Montes Claros, Pouso Alegre, Divinópolis, Belo Horizonte) | ✅ |
| `categorias_ferramenta` | Categorias de ferramenta (editável em Configurações), cada uma com flag `requer_afericao` | ✅ |
| `profiles` | Perfil de cada usuário, vinculado a `auth.users` | ✅ |
| `ferramentas` | Cadastro central de ferramentas | ✅ |
| `movimentacoes` | Log **append-only** de toda ação sobre uma ferramenta | ✅ |
| `manutencoes` | Registros de envio/retorno de conserto | ✅ |
| `auditorias_ferramentaria` | Cabeçalho de auditoria por filial | ✅ |
| `auditoria_itens` | Checklist de cada ferramenta numa auditoria | ✅ |
| `notifications` | Notificações in-app por usuário | ✅ |
| `password_reset_tokens` | Tokens de redefinição de senha (1h, sem acesso de cliente) | ✅ |

### `ferramentas`

| Coluna | Tipo | Observação |
|---|---|---|
| `codigo` | text | Único por filial |
| `categoria_id` | FK categorias_ferramenta | Determina se a ferramenta pede/mostra aferição (via `requer_afericao` da categoria) |
| `status` | enum | `disponivel`\|`com_colaborador`\|`em_afericao`\|`em_conserto`\|`extraviada`\|`baixada` — **só mutável por trigger** |
| `colaborador_atual_id` | FK profiles | Quem está com a ferramenta — **só mutável por trigger** |
| `data_ultima_afericao`, `data_proxima_afericao`, `data_saida_afericao`, `data_retorno_afericao` | date | **Só mutáveis por trigger**; só fazem sentido pra ferramentas de categoria com `requer_afericao=true` |

Reforço extra de defesa: `REVOKE UPDATE` + `GRANT UPDATE (nome, codigo, categoria_id, observacoes)` — as colunas operacionais não têm privilégio de UPDATE concedido ao papel `authenticated` em nível de coluna, então mesmo um bug de RLS não abriria brecha.

**Categoria controla a UI de aferição**: a tela de detalhe da ferramenta e o cadastro só mostram/pedem os campos de aferição (datas) e a ação "Enviar p/ Aferição" quando `categorias_ferramenta.requer_afericao` da categoria escolhida é `true`. Categorias seed: Ferramentas de medição, Equipamentos de elevação e Equipamentos de diagnóstico exigem aferição; as demais (manuais, pneumáticas, elétricas, especiais do fabricante, solda) não.

### Funções auxiliares de RLS (schema `private`)

`private.my_user_type()`, `private.my_filial_id()`, `private.is_admin_geral()`, `private.is_admin_area_ou_geral()`, `private.is_ativo()` — SECURITY DEFINER, `search_path=''`, schema não exposto na API REST, só `authenticated` tem `USAGE`.

---

## 6. Perfis de Usuário e Permissões

| Tipo | Escopo |
|---|---|
| `admin_geral` | Acesso total, todas as filiais, gestão de usuários irrestrita |
| `admin_area` | Limitado à própria filial; não promove a `admin_geral`; não move usuários entre filiais |
| `colaborador` | Vê e opera só a própria filial; sem acesso a Gestão de Usuários/Relatórios/Configurações de filiais |

Usuário protegido: `bruno.cesar@deva.com.br` não pode ser desativado por ninguém (trigger `fn_prevent_deactivate_protected_user`).

---

## 7. Máquina de Estados das Ferramentas

```
                    disponivel
        ┌───retirada──┼──envio_afericao──┼──(via Manutenções)──┐
        ▼             │                  ▼                     ▼
 com_colaborador       │             em_afericao           em_conserto
        │              │                  │                     │
   devolucao       extravio        retorno_afericao      (via Manutenções:
        │              │                  │               concluído ou baixada)
        └──────────────┼──────────────────┘                     │
                        ▼                                       │
                   extraviada ──reativacao(admin)──► disponivel │
                        │                                       │
                     baixa(admin)                          baixada
                        ▼                                       │
                    baixada ◄─────────reativacao(admin)─────────┘
```

Cada seta é validada por `fn_valida_transicao_movimentacao` (BEFORE INSERT) e aplicada por `fn_aplicar_movimentacao` (AFTER INSERT). Envio/retorno de conserto passam pela tabela `manutencoes` (motivo, fornecedor, prazo) e replicam automaticamente uma `movimentacao` espelho para manter o histórico único — um sinalizador de sessão (`app.internal_write`) impede que o cliente insira esses dois tipos de movimentação diretamente, contornando o formulário estruturado de Manutenções.

---

## 8. Edge Functions (API)

Endpoint base: `https://zdwkdfsqxkcrnkovdvba.supabase.co/functions/v1/{slug}`

| Function | verify_jwt | Descrição |
|---|---|---|
| `admin-create-user` | true | Cria usuário (admin_geral irrestrito; admin_area só na própria filial), senha aleatória 24 chars, e-mail de boas-vindas com link de setup |
| `admin-update-user` | true | Editar perfil / redefinir senha / ativar-desativar, com as mesmas restrições de filial e proteção do admin protegido |
| `admin-delete-user` | true | Hard delete, só `admin_geral` |
| `send-email` | false | Webhook de `notifications` (aferição próxima, retirada atrasada) + chamadas diretas (`welcome_with_setup`, `password_reset`, `reset_password_verify`) |

---

## 9. Auditorias

Fluxo simplificado (MVP): admin cria uma auditoria para uma filial → checklist com todas as ferramentas ativas dessa filial → marca cada uma como Encontrada / Não Encontrada / Danificada → ao avaliar 100%, finaliza. Sem geração de PDF nesta primeira versão (registrado como próxima leva, não implementado).

---

## 10. Modelo de Segurança

Mesma defesa em profundidade de 4 camadas do app de Gestão de Projetos: UX (Camada 4) → Edge Functions validam JWT+papel (Camada 3) → RLS por tabela (Camada 2) → Triggers como fonte da verdade para transições de estado, privilégio e proteção de conta (Camada 1). Nenhuma variável de ambiente/segredo aparece no front — só `SUPA_URL` e a `publishable key` (seguros por design, protegidos pelo RLS).

---

## 11. Automação de Alertas

`pg_cron` roda `fn_gerar_notificacoes_operacionais()` diariamente às 10h UTC (07h BRT), gerando notificações in-app (e e-mail, para os tipos críticos) para: aferição vencendo em ≤7 dias, e ferramentas emprestadas há mais de 30 dias sem devolução.

---

## 12. Deploy e Infraestrutura

- Repositório: `github.com/brunnocstt/FerramentariaDeva`, branch `main`, sem build step.
- Arquivo `CNAME` no repo aponta para `ferramentariadeva.albusdata.com.br`.
- **Para publicar qualquer mudança, é obrigatório fazer commit e push.**

### Variáveis de ambiente (Supabase Secrets)

| Variável | Status |
|---|---|
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Injetadas automaticamente |
| `APP_URL` | Configurada (`https://ferramentariadeva.albusdata.com.br`) |
| `SMTP_USER` / `ICLOUD_APP_PASSWORD` / `FROM_EMAIL` | **Pendente** — ver seção 13 |

---

## 13. Pendências Manuais

Ações fora do alcance do agente, que dependem do usuário:

1. **DNS**: criar registro CNAME `ferramentariadeva` → `brunnocstt.github.io` no provedor de `albusdata.com.br`.
2. **GitHub Pages**: em Settings → Pages do repo, ativar "Deploy from branch" `main` / `root` (o arquivo `CNAME` já está no repo).
3. **Turnstile**: adicionar `ferramentariadeva.albusdata.com.br` aos domínios permitidos do widget (site key `0x4AAAAAAD7cl8ffY5GysVNZ`, reaproveitado dos outros apps) no painel Cloudflare — ou criar um widget novo, se preferir isolar.
4. **Secrets de e-mail**: preencher `SMTP_USER`, `ICLOUD_APP_PASSWORD`, `FROM_EMAIL` no painel do projeto Supabase (Edge Functions → Secrets) — mesmas credenciais iCloud já usadas nos outros apps. Sem isso, e-mails (boas-vindas, redefinição de senha, alertas) não são enviados — mas o resto do sistema funciona normalmente.
5. **Template de e-mail de recuperação**: se decidir usar o link nativo do Supabase Auth no futuro, incluir `{{ .Token }}` no template (não necessário hoje, já que o fluxo usado é o token customizado via Edge Function).

---

*Documentação gerada em 07/08/2026. Para atualizar, edite este arquivo e faça `git push`.*
