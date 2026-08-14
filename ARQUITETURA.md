# Ferramentaria Deva — Arquitetura do Sistema

> **Versão:** 3.0 — 14/08/2026 (Rodada 3: acesso multi-filial, transferências, tela única de Estoque)
> **Autor:** Albus Data
> **URL de produção:** https://ferramentariadeva.albusdata.com.br (pendente configuração de DNS — ver seção 16)

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Stack Tecnológica](#2-stack-tecnológica)
3. [Diagrama Lógico](#3-diagrama-lógico)
4. [Frontend](#4-frontend)
5. [Banco de Dados](#5-banco-de-dados)
6. [Catálogo × Estoque × Empréstimos](#6-catálogo--estoque--empréstimos)
7. [Tela Estoque: Retiradas, Devoluções e Painel em Tempo Real](#7-tela-estoque-retiradas-devoluções-e-painel-em-tempo-real)
8. [Acesso Multi-Filial e Transferências entre Filiais](#8-acesso-multi-filial-e-transferências-entre-filiais)
9. [Perfis de Usuário e Permissões](#9-perfis-de-usuário-e-permissões)
10. [Máquina de Estados das Ferramentas](#10-máquina-de-estados-das-ferramentas)
11. [Edge Functions (API)](#11-edge-functions-api)
12. [Auditorias](#12-auditorias)
13. [Modelo de Segurança](#13-modelo-de-segurança)
14. [Automação de Alertas](#14-automação-de-alertas)
15. [Deploy e Infraestrutura](#15-deploy-e-infraestrutura)
16. [Pendências Manuais](#16-pendências-manuais)

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
    └── Views         DashboardView (+ UsoAoVivoPanel), FerramentasView — tela "Estoque"
                       (catálogo, estoque, TransferenciasPendentesPanel, ModalNovaRetirada/
                       ModalDevolucao com RetiradaColaborador/DevolucaoColaborador),
                       MovimentacoesView, ManutencoesView, AuditoriasView/AuditoriaExecucaoView,
                       GestaoUsuariosView, RelatoriosView, ConfiguracoesView
```

Reset de senha usa o mesmo padrão definitivo do app de referência: token customizado de 64 caracteres via `?reset_token=`, capturado **antes** de qualquer código Supabase rodar, independente do fluxo nativo `PASSWORD_RECOVERY` (incompatível com SPA sem build). Não existe `reset-password.html` separado neste app — o fluxo native de recovery link não é usado, só o token customizado.

---

## 5. Banco de Dados

### Tabelas

| Tabela | Descrição | RLS |
|---|---|---|
| `filiais` | As 6 filiais com oficina (Betim, Juiz de Fora, Montes Claros, Pouso Alegre, Divinópolis, Belo Horizonte), cada uma com `codigo_barras` opcional (prefixo do código de barras do crachá — ver seção 7) | ✅ |
| `categorias_ferramenta` | Categorias de ferramenta (editável em Configurações), cada uma com flags `requer_afericao` e `controle_individual` | ✅ |
| `profiles` | Perfil de cada usuário, vinculado a `auth.users`, com `matricula` (crachá) opcional — única só **dentro da filial** (`unique(filial_id,matricula)`), não globalmente | ✅ |
| `acessos_filial` | Acesso operacional **extra** de uma pessoa a filiais além da própria (`profile_id, filial_id`) — ver seção 8 | ✅ |
| `ferramentas_catalogo` | Cadastro **global** de tipos/modelos de ferramenta (não tem filial) | ✅ |
| `ferramentas_unidade` | Unidade física individual de um tipo do catálogo, numa filial, com código próprio | ✅ |
| `estoque_pool` | Quantidade total de um tipo do catálogo numa filial, sem código individual | ✅ |
| `emprestimos` | Retiradas/devoluções contra um `estoque_pool` (múltiplas simultâneas) | ✅ |
| `transferencias_ferramenta` | Pedido de transferência de uma `ferramenta_unidade` entre filiais, com aprovação — ver seção 8 | ✅ |
| `movimentacoes` | Log **append-only** de toda ação sobre uma `ferramenta_unidade` | ✅ |
| `manutencoes` | Registros de envio/retorno de conserto (só unidades individuais) | ✅ |
| `auditorias_ferramentaria` | Cabeçalho de auditoria por filial | ✅ |
| `auditoria_itens` | Checklist de cada `ferramenta_unidade` numa auditoria | ✅ |
| `notifications` | Notificações in-app por usuário | ✅ |
| `password_reset_tokens` | Tokens de redefinição de senha (1h, sem acesso de cliente) | ✅ |

> A tabela `ferramentas` da Rodada 1 (uma linha por unidade física, sem separar catálogo de estoque) foi **dropada** na Rodada 2 e substituída pelo modelo catálogo/unidade/pool descrito na seção 6 — ver justificativa lá.

### `ferramentas_unidade`

| Coluna | Tipo | Observação |
|---|---|---|
| `catalogo_id` | FK ferramentas_catalogo | Define nome/categoria (não duplicados aqui) |
| `filial_id` | FK filiais | Cada unidade pertence a uma filial |
| `codigo` | text | Único, identifica a unidade física |
| `status` | enum | `disponivel`\|`com_colaborador`\|`em_afericao`\|`em_conserto`\|`extraviada`\|`baixada` — **só mutável por trigger** |
| `colaborador_atual_id` | FK profiles | Quem está com a ferramenta — **só mutável por trigger** |
| `data_retirada_atual` | timestamptz | Gravada na retirada, limpa na devolução — alimenta o painel "há quanto tempo" (seção 7) |
| `data_ultima_afericao`, `data_proxima_afericao`, `data_saida_afericao`, `data_retorno_afericao` | date | **Só mutáveis por trigger**; só fazem sentido pra categoria com `requer_afericao=true` |

Reforço extra de defesa: `REVOKE UPDATE` + `GRANT UPDATE` só nas colunas cadastrais (`codigo`, `observacoes`) — as colunas operacionais não têm privilégio de UPDATE concedido ao papel `authenticated` em nível de coluna, então mesmo um bug de RLS não abriria brecha.

**Categoria controla a UI de aferição**: a tela de detalhe da ferramenta e o cadastro só mostram/pedem os campos de aferição (datas) e a ação "Enviar p/ Aferição" quando `categorias_ferramenta.requer_afericao` da categoria escolhida é `true`. Categorias seed: Ferramentas de medição, Equipamentos de elevação e Equipamentos de diagnóstico exigem aferição; as demais (manuais, pneumáticas, elétricas, especiais do fabricante, solda) não.

### Funções auxiliares de RLS (schema `private`)

`private.my_user_type()`, `private.my_filial_id()`, `private.is_admin_geral()`, `private.is_admin_area_ou_geral()`, `private.is_ativo()` — SECURITY DEFINER, `search_path=''`, schema não exposto na API REST, só `authenticated` tem `USAGE`.

---

## 6. Catálogo × Estoque × Empréstimos

Identificados 3 problemas reais no modelo da Rodada 1 (que tratava toda ferramenta como unidade física única, com um único dono por vez): (1) muitas ferramentas existem em várias unidades idênticas, sem serial próprio; (2) o mesmo tipo de ferramenta pode existir numa filial e não noutra — cadastro e estoque por filial são coisas distintas; (3) faltava um fluxo de entrega em tempo real pensado para leitor de código de barras.

```
ferramentas_catalogo  (global, 1 linha por "tipo/modelo" — sem filial)
        │
        ├── controle_individual = true  ──► ferramentas_unidade (1 linha por unidade física,
        │                                    por filial, com código — igual à Rodada 1, mas
        │                                    referenciando o catálogo em vez de nome embutido)
        │
        └── controle_individual = false ──► estoque_pool (1 linha por filial, só quantidade_total)
                                             + emprestimos (retiradas/devoluções contra esse
                                               estoque, várias simultâneas, sem "dono único")
```

`categorias_ferramenta.controle_individual` decide qual dos dois caminhos uma categoria segue. Categorias com `requer_afericao=true` são **obrigadas** a `controle_individual=true` — reforçado por `CHECK chk_afericao_exige_individual` (não dá pra calibrar "8 torquímetros" como um bloco só).

`ferramentas_catalogo`: RLS de SELECT liberado a todo autenticado; INSERT/UPDATE só `admin_geral` (catálogo é compartilhado entre filiais, evita duplicidade tipo "Chave de Fenda" cadastrada duas vezes por admins de filiais diferentes).

`estoque_pool` (`catalogo_id, filial_id, quantidade_total`, único por par): RLS escopada por filial, escrita por `admin_geral`/`admin_area` da própria filial. O modal "Nova Ferramenta" soma à `quantidade_total` existente em vez de duplicar a linha quando já há estoque daquele tipo na filial.

`emprestimos` (`estoque_id, colaborador_id, quantidade, data_retirada, data_devolucao, registrado_por, observacao`): trigger `fn_valida_emprestimo` (BEFORE INSERT) bloqueia a retirada se `quantidade` pedida > saldo disponível (`quantidade_total` − soma dos empréstimos ainda sem devolução), com mensagem clara ("Não há saldo suficiente nesse estoque (disponível: N)."). `data_devolucao` só é alterável via UPDATE restrito por coluna (mesmo padrão de `REVOKE`/`GRANT` de `ferramentas_unidade`), e um segundo trigger (`fn_valida_devolucao_emprestimo`) impede devolver duas vezes o mesmo empréstimo.

Fora de escopo (registrado para não ser esquecido, não implementado): auditoria de itens em pool (a tela de Auditorias cobre só `ferramentas_unidade`, que é o que faz sentido para um checklist item-a-item); extravio/conserto de item em pool — ajuste fica manual, admin corrige `quantidade_total` direto por enquanto.

---

## 7. Tela Estoque: Retiradas, Devoluções e Painel em Tempo Real

Desde a Rodada 3, **não existe mais uma tela "Retiradas" separada** — o pedido do usuário foi reduzir o número de telas do app. Tudo que envolve o ferramental do dia a dia (catálogo, estoque por filial, retirar, devolver, transferir) vive numa única tela, **"Estoque"** (`FerramentasView`), incluindo pra `colaborador` (que só enxerga esse item no menu).

**Fluxo do ferramenteiro:** os botões "Nova Retirada" e "Devolver Ferramenta" no topo da tela Estoque abrem, respectivamente, `ModalNovaRetirada` e `ModalDevolucao`. Os dois começam pelo mesmo componente `CampoBuscaCracha`: o leitor de código de barras USB do crachá funciona como teclado — "digita" o código e envia Enter sozinho, então basta um `<input>` de texto normal com `onSubmit` de formulário, sem integração especial.

**Formato do código de barras do crachá:** o código lido traz filial + matrícula no mesmo número (ex.: `055003000830` → filial `55003` + matrícula `830`). A função `buscarColaboradorPorCracha` divide o código lido **ao meio** e converte cada metade pra inteiro (descarta os zeros à esquerda dos dois lados automaticamente, cobrindo matrícula de 3 a 4 dígitos sem configuração extra). A primeira metade é comparada com `filiais.codigo_barras` (cadastrado por filial em Configurações → Filiais — ver `FilialRow`); a segunda, com `profiles.matricula` **dentro daquela filial**. Entradas curtas (< 8 dígitos, ex. digitação manual de só "830") pulam essa divisão e buscam só por matrícula, escopada automaticamente pelo RLS de `profiles` à filial de quem está operando a tela. Como a mesma matrícula pode se repetir em filiais diferentes, `profiles.matricula` não é mais globalmente única — a unicidade real é `unique(filial_id, matricula)` (migration `0004_codigo_barras_cracha.sql`).

- **Retirar** (`RetiradaColaborador`): lista as ferramentas disponíveis na filial do colaborador — unidades individuais livres e tipos em pool com saldo (com campo de quantidade). Ao confirmar, grava um INSERT em `movimentacoes` (tipo `retirada`, unidade individual) ou em `emprestimos` (pool).
- **Devolver** (`DevolucaoColaborador`): escolhe o colaborador **sem reler o crachá**, mostra tudo que está com ele (unidades + empréstimos em aberto) como uma lista de **checkboxes** — dá pra marcar mais de uma ferramenta e devolver todas de uma vez com um único "Confirmar Devolução", que aplica um INSERT/UPDATE por item selecionado em sequência.

**Painel "Ferramentas em Uso" (Dashboard, `admin_geral`/`admin_area`)**: componente `UsoAoVivoPanel` lista ao vivo quem está com o quê e há quanto tempo (`data_retirada_atual` de `ferramentas_unidade` / `data_retirada` de `emprestimos`), com o texto "há Xmin/Xh/Xd" recalculado a cada 30s via `setInterval` local. Atualização **sem reload**: assina `supabase.channel(...).on("postgres_changes",{table:"ferramentas_unidade"|"emprestimos"},...)` — mesmo padrão usado para `demands-rt`/`notif-rt` no app de Gestão de Projetos. As tabelas `ferramentas_unidade`, `emprestimos` e `movimentacoes` estão habilitadas na publicação `supabase_realtime`. Testado com duas abas logadas simultaneamente: uma retirada/devolução numa aba reflete na outra sem qualquer ação manual.

---

## 8. Acesso Multi-Filial e Transferências entre Filiais

Motivado por dois pedidos do usuário: (1) uma pessoa pode precisar operar o ferramental de mais de uma filial sem ser **gestora** de todas elas; (2) precisa existir um jeito real de mover uma ferramenta específica de uma filial pra outra, com aprovação.

### Acesso operacional × autoridade de gestor

Dois conceitos que antes eram a mesma coisa (`profiles.filial_id`) se separam:

- **Filial "de casa"** (`profiles.filial_id`, sentido inalterado): onde a matrícula da pessoa vale pro crachá, e — pra `admin_area` — a filial da qual ela é **gestora** (autoridade de aprovação de transferências recebidas).
- **Acesso operacional extra** (`acessos_filial`, novo): filiais adicionais cujo estoque a pessoa pode ver/operar (retirar, devolver, solicitar transferência) **sem** ser gestora de lá. Só `admin_geral` concede — editável em Gestão de Usuários (`ModalUsuario`, campo "Filiais com acesso extra", multi-select de checkboxes).

Helper SQL (`private.tem_acesso_filial(f_id)`, `SECURITY DEFINER`): `is_admin_geral() OR f_id = minha filial_id OR existe linha em acessos_filial`. Substituiu `filial_id = private.my_filial_id()` em **toda** RLS/trigger que decide "essa pessoa pode ver/operar essa filial" — `ferramentas_unidade`, `estoque_pool`, `emprestimos`, `movimentacoes`, `manutencoes`, `auditorias_ferramentaria`, `auditoria_itens` (migration `0006_acesso_multifilial_transferencias.sql`). `private.my_filial_id()` continua existindo só pro que é mesmo "filial de casa" (matrícula, e edição de outro usuário em `fn_validate_admin_area_profile_update`, que fica de fora de propósito — um admin_area só edita colaboradores da própria filial, mesmo com acesso extra a outras).

No front, `App.initUser()` carrega `acessos_filial` do usuário e monta `profile.filialIds` (array de uuid) e `profile.filiaisAcesso` (array `{id,nome}`). Toda tela que antes filtrava por `profile.filialId` único agora usa `.in("filial_id", profile.filialIds)`, e o filtro de filial na tela Estoque (antes só pra `admin_geral`) passa a aparecer sempre que `profile.filiaisAcesso.length > 1`.

### Transferências

Vale **só para unidades individuais** (`ferramentas_unidade`) — estoque em pool continua sendo ajustado manualmente pelo admin, como já era desde a Rodada 2.

Tabela `transferencias_ferramenta` (`ferramenta_id, filial_origem_id, filial_destino_id, solicitante_id, status, aprovador_id, motivo, resposta`), com `status` em `pendente`/`aprovada`/`rejeitada`/`cancelada`:

1. **Solicitar** (ação "Transferir para Outra Filial" em `FerramentaDetalheModal`, visível quando `status=disponivel` e a pessoa acessa mais de uma filial): trigger `fn_valida_transferencia_solicitacao` exige que a ferramenta esteja `disponivel`, deriva `filial_origem_id` da própria ferramenta (não vem do cliente) e exige `tem_acesso_filial` nas duas pontas — origem **e** destino. `fn_aplicar_transferencia_solicitacao` marca a ferramenta como `em_transferencia` (novo valor de `status_ferramenta`), bloqueando qualquer outra ação nela enquanto pendente. `fn_notificar_transferencia_solicitada` avisa (`notifications`) todo `admin_area` da filial de destino.
2. **Decidir** (aprovar/rejeitar): só quem é `admin_area` da filial de **destino**, ou `admin_geral` — `fn_valida_transferencia_decisao` bloqueia qualquer outra pessoa, incluindo o gestor da filial de origem. Cancelar uma solicitação ainda pendente é reservado a quem a criou.
3. **Aplicar**: se aprovada, `fn_aplicar_transferencia_decisao` muda `ferramentas_unidade.filial_id` pra destino, `status` volta a `disponivel`, e insere uma `movimentacoes` (tipo `transferencia`, novo valor de `tipo_movimentacao`) via o mesmo flag `app.internal_write` usado pelo fluxo de conserto. Se rejeitada/cancelada, a ferramenta volta a `disponivel` na filial de origem. Notifica o solicitante da decisão.

RLS de `transferencias_ferramenta`: SELECT liberado a quem tem acesso à origem, ao destino, ou é `admin_geral`; UPDATE liberado só nas colunas `status`/`resposta` (`REVOKE`/`GRANT` por coluna); a trigger de decisão é quem valida de fato quem pode aprovar/rejeitar/cancelar — mesmo padrão de defesa em profundidade do resto do sistema. Tabela habilitada em `supabase_realtime`, alimentando `TransferenciasPendentesPanel` (seção no topo da tela Estoque) sem precisar recarregar a página.

Testado via simulação de sessão autenticada em SQL (`set_config('request.jwt.claim.sub', ...)`, sem precisar logar de fato): pedido válido (acesso às duas pontas) cria a pendência e bloqueia a ferramenta; pedido sem acesso à filial de destino é rejeitado pela trigger; gestor errado (de outra filial) não consegue decidir; gestor certo aprova e a ferramenta muda de filial corretamente, com `movimentacoes` registrada; rejeição devolve a ferramenta à origem; cancelamento só funciona para quem solicitou; decidir uma solicitação já decidida é bloqueado.

**Bug encontrado e corrigido durante esse teste**: `fn_aplicar_movimentacao` (que aplica o efeito de cada tipo de `movimentacao` em `ferramentas_unidade`) tinha um `CASE` sem `ELSE` e sem braço pra `'transferencia'` — a primeira aprovação de teste quebrou com "case not found". Corrigido em `0007_fix_aplicar_movimentacao_transferencia.sql` adicionando um braço no-op (o efeito real da transferência já é aplicado por `fn_aplicar_transferencia_decisao` antes dessa movimentação-espelho ser inserida).

---

## 9. Perfis de Usuário e Permissões

| Tipo | Escopo |
|---|---|
| `admin_geral` | Acesso total, todas as filiais, gestão de usuários irrestrita |
| `admin_area` | Limitado à própria filial; não promove a `admin_geral`; não move usuários entre filiais |
| `colaborador` | Vê e opera só a própria filial; sem acesso a Gestão de Usuários/Relatórios/Configurações de filiais |

Usuário protegido: `bruno.cesar@deva.com.br` não pode ser desativado por ninguém (trigger `fn_prevent_deactivate_protected_user`).

---

## 10. Máquina de Estados das Ferramentas

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

Essa máquina de estados vale só para `ferramentas_unidade` (individuais). Itens em pool têm uma máquina bem mais simples, própria de `emprestimos`: `retirada` (INSERT, validada por saldo) → `devolucao` (UPDATE de `data_devolucao`, validada contra devolução duplicada) — ver seção 6.

---

## 11. Edge Functions (API)

Endpoint base: `https://zdwkdfsqxkcrnkovdvba.supabase.co/functions/v1/{slug}`

| Function | verify_jwt | Descrição |
|---|---|---|
| `admin-create-user` | true | Cria usuário (admin_geral irrestrito; admin_area só na própria filial), senha aleatória 24 chars, e-mail de boas-vindas com link de setup |
| `admin-update-user` | true | Editar perfil / redefinir senha / ativar-desativar, com as mesmas restrições de filial e proteção do admin protegido |
| `admin-delete-user` | true | Hard delete, só `admin_geral` |
| `send-email` | false | Webhook de `notifications` (aferição próxima, retirada atrasada) + chamadas diretas (`welcome_with_setup`, `password_reset`, `reset_password_verify`) |

---

## 12. Auditorias

Fluxo simplificado (MVP): admin cria uma auditoria para uma filial → checklist com todas as ferramentas ativas dessa filial → marca cada uma como Encontrada / Não Encontrada / Danificada → ao avaliar 100%, finaliza. Sem geração de PDF nesta primeira versão (registrado como próxima leva, não implementado).

---

## 13. Modelo de Segurança

Mesma defesa em profundidade de 4 camadas do app de Gestão de Projetos: UX (Camada 4) → Edge Functions validam JWT+papel (Camada 3) → RLS por tabela (Camada 2) → Triggers como fonte da verdade para transições de estado, privilégio e proteção de conta (Camada 1). Nenhuma variável de ambiente/segredo aparece no front — só `SUPA_URL` e a `publishable key` (seguros por design, protegidos pelo RLS).

---

## 14. Automação de Alertas

`pg_cron` roda `fn_gerar_notificacoes_operacionais()` diariamente às 10h UTC (07h BRT), gerando notificações in-app (e e-mail, para os tipos críticos) para: aferição vencendo em ≤7 dias, e ferramentas emprestadas há mais de 30 dias sem devolução.

---

## 15. Deploy e Infraestrutura

- Repositório: `github.com/brunnocstt/FerramentariaDeva`, branch `main`, sem build step.
- Arquivo `CNAME` no repo aponta para `ferramentariadeva.albusdata.com.br`.
- **Para publicar qualquer mudança, é obrigatório fazer commit e push.**

### Variáveis de ambiente (Supabase Secrets)

| Variável | Status |
|---|---|
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Injetadas automaticamente |
| `APP_URL` | Configurada (`https://ferramentariadeva.albusdata.com.br`) |
| `SMTP_USER` / `ICLOUD_APP_PASSWORD` / `FROM_EMAIL` | **Pendente** — ver seção 16 |

---

## 16. Pendências Manuais

Ações fora do alcance do agente, que dependem do usuário:

1. **DNS**: criar registro CNAME `ferramentariadeva` → `brunnocstt.github.io` no provedor de `albusdata.com.br`.
2. **GitHub Pages**: em Settings → Pages do repo, ativar "Deploy from branch" `main` / `root` (o arquivo `CNAME` já está no repo).
3. **Turnstile**: adicionar `ferramentariadeva.albusdata.com.br` aos domínios permitidos do widget (site key `0x4AAAAAAD7cl8ffY5GysVNZ`, reaproveitado dos outros apps) no painel Cloudflare — ou criar um widget novo, se preferir isolar.
4. **Secrets de e-mail**: preencher `SMTP_USER`, `ICLOUD_APP_PASSWORD`, `FROM_EMAIL` no painel do projeto Supabase (Edge Functions → Secrets) — mesmas credenciais iCloud já usadas nos outros apps. Sem isso, e-mails (boas-vindas, redefinição de senha, alertas) não são enviados — mas o resto do sistema funciona normalmente.
5. **Template de e-mail de recuperação**: se decidir usar o link nativo do Supabase Auth no futuro, incluir `{{ .Token }}` no template (não necessário hoje, já que o fluxo usado é o token customizado via Edge Function).

---

*Documentação gerada em 07/08/2026, atualizada em 13/08/2026 (Rodada 2) e 14/08/2026 (Rodada 3). Para atualizar, edite este arquivo e faça `git push`.*
