# Nexus ERP — World Post

ERP interno para **Fábrica, Logística e Contábil**, construído como mais um
"sistema filho" do Portal World Post — usa o **mesmo projeto Supabase** e o
mesmo login (SSO via token), sem precisar de outro banco ou outra conta.

## O que já funciona

- **Cadastros**: Produtos, Parceiros (clientes/fornecedores), Depósitos, Transportadoras.
- **Compras**: pedido de compra com itens → recebimento parcial/total gera entrada em estoque.
- **Estoque / Logística**: kardex completo (todas as movimentações), saldo por produto/depósito, ajuste manual.
- **Produção (Fábrica)**: estrutura de produto (BOM) e ordens de produção — apontar produção consome os componentes da BOM e gera o produto acabado no estoque, automaticamente.
- **Vendas**: pedido de venda com itens → expedição parcial/total gera saída de estoque (valida saldo disponível antes de expedir).
- **Financeiro / Contábil**: plano de contas, lançamentos em partidas dobradas (o sistema não deixa salvar um lançamento em que débito ≠ crédito) e um razão/balancete simples por conta.
- **Dashboard** com KPIs (valor em estoque, pedidos em aberto, produção ativa, produtos abaixo do mínimo).

Todo o app é um único arquivo estático (`erp/index.html`), no mesmo padrão do
Portal (`index.html` na raiz) — sem build, sem dependências além do
Supabase JS via CDN.

## Como colocar no ar

### 1. Rodar o schema no Supabase

No mesmo projeto Supabase já usado pelo portal (onde já existem
`portal_profiles` e `portal_permissions`):

1. Abra **SQL Editor** no painel do Supabase.
2. Cole o conteúdo de [`schema.sql`](./schema.sql) e execute.

Isso cria todas as tabelas `erp_*`, as políticas de RLS, as funções
transacionais (RPC) e um plano de contas inicial.

O schema foi testado ponta a ponta (compras → recebimento, BOM → apontamento
de produção, lançamento contábil balanceado/desbalanceado) em um Postgres
local antes de ser incluído aqui.

### 2. Publicar o arquivo

Basta publicar a pasta `erp/` junto com o resto do repositório (GitHub
Pages, Netlify, etc.) — o app já está linkado como tile **"Nexus ERP"** no
portal (`index.html`, array `SYSTEMS`), apontando para `erp/index.html`
(caminho relativo, funciona em qualquer domínio onde o repositório for
publicado).

### 3. Quem pode acessar

O ERP reaproveita as mesmas contas do portal: qualquer usuário com
`status = 'active'` em `portal_profiles` consegue entrar (tanto pelo tile —
SSO automático — quanto abrindo `erp/index.html` diretamente e fazendo
login com e-mail/senha).

Permissões por papel (`role` em `portal_profiles`):

| Ação | usuário | líder | admin |
|---|---|---|---|
| Ver tudo (cadastros, pedidos, estoque, razão) | ✅ | ✅ | ✅ |
| Criar/editar cadastros e lançar operações (pedidos, produção, ajustes) | ✅ | ✅ | ✅ |
| Excluir qualquer registro | ❌ | ✅ | ✅ |
| Criar/editar Plano de Contas e Lançamentos Contábeis | ❌ | ✅ | ✅ |

Esses controles são reforçados no banco (Row Level Security), não apenas na
tela — mesmo alguém manipulando as chamadas diretamente não consegue passar
das regras.

## Como o SSO funciona

O portal (`accessSystem()` em `index.html`) abre o tile passando o token de
sessão atual no hash da URL:

```
erp/index.html#access_token=...&refresh_token=...&type=portal_sso
```

O `erp/index.html` lê esse hash no boot, chama
`sb.auth.setSession({access_token, refresh_token})` e limpa a URL. Se não
houver token (acesso direto), ele cai na tela de login normal.

## Extensões possíveis (próximos passos)

- Contas a pagar/receber detalhadas (hoje o financeiro é só partida dobrada manual).
- Custo médio automático (hoje o custo usado é o `cost_price` cadastrado no produto).
- Múltiplas estruturas (BOM) ativas por produto com seleção de "BOM padrão".
- Relatórios de DRE/Balanço a partir do razão.
- Etiquetas/rastreabilidade por lote e número de série.
