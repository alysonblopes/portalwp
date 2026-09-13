# Nexus ERP — World Post

ERP interno para **Fábrica, Logística e Contábil**.

> ⚠️ **Estado atual: fase de testes.** O login foi removido de propósito e o
> app aponta para um projeto Supabase de teste, separado do Portal World
> Post em produção. Qualquer pessoa com o link e a chave anon deste projeto
> lê e escreve nos dados — não é o modo final, é só para validar o
> funcionamento antes de reativar autenticação/RLS.

## O que já funciona

- **Cadastros**: Produtos, Parceiros (clientes/fornecedores), Depósitos, Transportadoras.
- **Compras**: pedido de compra com itens → recebimento parcial/total gera entrada em estoque.
- **Estoque / Logística**: kardex completo (todas as movimentações), saldo por produto/depósito, ajuste manual.
- **Produção (Fábrica)**: estrutura de produto (BOM) e ordens de produção — apontar produção consome os componentes da BOM e gera o produto acabado no estoque, automaticamente.
- **Vendas**: pedido de venda com itens → expedição parcial/total gera saída de estoque (valida saldo disponível antes de expedir).
- **Financeiro / Contábil**: plano de contas, lançamentos em partidas dobradas (o sistema não deixa salvar um lançamento em que débito ≠ crédito) e um razão/balancete simples por conta.
- **Dashboard** com KPIs (valor em estoque, pedidos em aberto, produção ativa, produtos abaixo do mínimo).

Todo o app é um único arquivo estático (`erp/index.html`) — sem build, sem
dependências além do Supabase JS via CDN. Isso é o que torna viável embrulhar
o mesmo arquivo num executável Windows ou app mobile mais adiante (veja
"Empacotar como app" abaixo).

## Dois schemas — qual usar

| Arquivo | Quando usar |
|---|---|
| **`schema_test.sql`** | Projeto Supabase novo/vazio, só para teste. Sem `portal_profiles`, sem RLS, sem checagem de permissão nas funções. É o que está em uso agora. |
| **`schema.sql`** | Quando o ERP for reintegrado ao Portal World Post (mesmo projeto do portal, com login e RLS por papel). |

Os dois foram testados ponta a ponta (compras → recebimento, BOM →
apontamento de produção, lançamento contábil balanceado/desbalanceado) num
Postgres local antes de entrar no repositório.

### Configuração atual (teste)

`erp/index.html` está apontando para:

```
SUPABASE_URL = https://bdvbuiuzkudwayibbjaz.supabase.co
```

Para colocar esse projeto no ar:

1. Abra o **SQL Editor** desse projeto no painel do Supabase.
2. Cole o conteúdo de [`schema_test.sql`](./schema_test.sql) e execute.
3. Publique/abra `erp/index.html` — não tem tela de login, cai direto no
   Dashboard.

### Voltando para produção (com login)

Quando for usar dados reais de novo:

1. Rode `schema.sql` no projeto Supabase do Portal World Post.
2. Troque `SUPABASE_URL`/`SUPABASE_KEY` em `erp/index.html` de volta para o
   projeto do portal.
3. Reative a tela e a lógica de login (o commit anterior a este tem a
   versão completa com SSO — usar como referência para restaurar).

## PWA — instalar como app (Windows / Android / iOS)

O Nexus ERP agora é uma **PWA instalável**. Arquivos adicionados:

- `manifest.json` — nome, ícones e modo `standalone` (abre em janela
  própria, sem barra de endereço do navegador).
- `service-worker.js` — cacheia o "shell" do app (HTML, manifest, ícones)
  pra abrir mais rápido e continuar funcionando offline na navegação;
  chamadas ao Supabase continuam precisando de internet, é onde os dados
  realmente moram.
- `icons/` — ícones gerados (192, 512, 512 maskable, apple-touch-icon,
  favicon), no azul da marca com o monograma "N".

Testado localmente (Chromium via Playwright): o service worker registra,
ativa e cacheia os arquivos do shell corretamente.

### Como instalar

**Windows (Chrome ou Edge)**
1. Abra `erp/index.html` publicado (precisa estar em `http://` ou
   `https://` — PWA não instala abrindo o arquivo direto do disco).
2. Clique no botão **"⬇ Instalar App"** que aparece no topo, ou no ícone
   de instalação que o próprio navegador mostra na barra de endereço.
3. Abre como um app de janela própria, com ícone e atalho — sem precisar
   gerar `.exe`.

**Android (Chrome)**: mesma coisa — botão "Instalar App" ou menu
"Adicionar à tela inicial".

**iPhone/iPad (Safari)**: o iOS não mostra o botão de instalar
automaticamente (Apple não implementa esse evento) — use **Compartilhar →
Adicionar à Tela de Início**. Os metadados pra isso (`apple-touch-icon`,
`apple-mobile-web-app-capable`) já estão no `<head>`.

### Se um dia precisar de app "de verdade" na loja

O PWA cobre instalar/usar como app sem loja. Se depois quiser publicar na
Play Store / Microsoft Store, ou embrulhar num instalador `.exe` clássico,
dá pra reaproveitar o mesmo `erp/index.html` com
[Tauri](https://tauri.app/)/[Electron](https://www.electronjs.org/)
(Windows) ou [Capacitor](https://capacitorjs.com/) (Android/iOS) — não foi
feito agora porque o PWA já resolve o teste com bem menos esforço.

## Extensões possíveis (próximos passos)

- Contas a pagar/receber detalhadas (hoje o financeiro é só partida dobrada manual).
- Custo médio automático (hoje o custo usado é o `cost_price` cadastrado no produto).
- Múltiplas estruturas (BOM) ativas por produto com seleção de "BOM padrão".
- Relatórios de DRE/Balanço a partir do razão.
- Etiquetas/rastreabilidade por lote e número de série.
