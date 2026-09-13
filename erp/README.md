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

## Empacotar como app (Windows / celular)

Como o ERP é um HTML/JS estático sem backend próprio (toda a lógica vive no
Supabase), dá para embrulhar esse mesmo arquivo em:

- **Windows**: [Electron](https://www.electronjs.org/) ou
  [Tauri](https://tauri.app/) — abre `erp/index.html` numa janela nativa e
  gera um `.exe`. Tauri gera instalador bem menor (usa o WebView do
  Windows em vez de empacotar um Chromium inteiro).
- **Celular (Android/iOS)**: [Capacitor](https://capacitorjs.com/) (da
  equipe do Ionic) — mesma ideia, empacota o HTML num app nativo instalável
  na loja ou via APK direto.
- **Alternativa mais simples**: transformar em **PWA** (adicionar um
  `manifest.json` + service worker) — instala como app no celular e no
  Windows direto pelo navegador (Chrome/Edge), sem precisar gerar
  executável nem publicar em loja. Menor esforço, funciona hoje.

Nenhuma dessas opções está implementada ainda — nenhuma mudou o app em si.
Antes de escolher uma, vale decidir: precisa de loja (Play Store/Microsoft
Store) e ícone/instalador "de verdade", ou instalar como PWA já resolve o
teste?

## Extensões possíveis (próximos passos)

- Contas a pagar/receber detalhadas (hoje o financeiro é só partida dobrada manual).
- Custo médio automático (hoje o custo usado é o `cost_price` cadastrado no produto).
- Múltiplas estruturas (BOM) ativas por produto com seleção de "BOM padrão".
- Relatórios de DRE/Balanço a partir do razão.
- Etiquetas/rastreabilidade por lote e número de série.
