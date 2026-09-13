-- ══════════════════════════════════════════════════════════════════
-- NEXUS ERP — World Post
-- Schema Supabase (Postgres) — Fábrica · Logística · Contábil
--
-- Execute este arquivo inteiro no SQL Editor do Supabase (mesmo projeto
-- usado pelo portal, onde já existem as tabelas portal_profiles e
-- portal_permissions). Todas as tabelas do ERP usam o prefixo "erp_"
-- para não colidir com nada do portal.
-- ══════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ──────────────────────────────────────────────
-- 1. HELPERS DE PERMISSÃO
--    Reaproveita portal_profiles (role: admin | lider | usuario,
--    status: active | inactive) como fonte de verdade de quem pode
--    acessar o ERP.
-- ──────────────────────────────────────────────
create or replace function erp_is_active_user()
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from portal_profiles
    where id = auth.uid() and status = 'active'
  );
$$;

create or replace function erp_is_manager()
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from portal_profiles
    where id = auth.uid() and status = 'active' and role in ('admin','lider')
  );
$$;

create or replace function erp_is_admin()
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from portal_profiles
    where id = auth.uid() and status = 'active' and role = 'admin'
  );
$$;

-- ──────────────────────────────────────────────
-- 2. CADASTROS BASE
-- ──────────────────────────────────────────────
create table if not exists erp_products (
  id uuid primary key default gen_random_uuid(),
  sku text unique not null,
  name text not null,
  description text,
  unit text not null default 'UN',
  type text not null default 'produto_acabado'
    check (type in ('materia_prima','produto_acabado','revenda','servico')),
  cost_price numeric(14,2) not null default 0,
  sale_price numeric(14,2) not null default 0,
  min_stock numeric(14,3) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists erp_partners (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('cliente','fornecedor','ambos')),
  name text not null,
  document text,
  email text,
  phone text,
  address text,
  city text,
  state text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists erp_warehouses (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  location text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists erp_carriers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  document text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ──────────────────────────────────────────────
-- 3. COMPRAS
-- ──────────────────────────────────────────────
create table if not exists erp_purchase_orders (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity,
  supplier_id uuid not null references erp_partners(id),
  warehouse_id uuid not null references erp_warehouses(id),
  status text not null default 'rascunho'
    check (status in ('rascunho','aprovado','recebido_parcial','recebido','cancelado')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists erp_purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references erp_purchase_orders(id) on delete cascade,
  product_id uuid not null references erp_products(id),
  qty numeric(14,3) not null check (qty > 0),
  qty_received numeric(14,3) not null default 0,
  unit_price numeric(14,2) not null default 0
);

-- ──────────────────────────────────────────────
-- 4. VENDAS
-- ──────────────────────────────────────────────
create table if not exists erp_sales_orders (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity,
  customer_id uuid not null references erp_partners(id),
  warehouse_id uuid not null references erp_warehouses(id),
  carrier_id uuid references erp_carriers(id),
  status text not null default 'rascunho'
    check (status in ('rascunho','confirmado','expedido_parcial','expedido','cancelado')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists erp_sales_order_items (
  id uuid primary key default gen_random_uuid(),
  sales_order_id uuid not null references erp_sales_orders(id) on delete cascade,
  product_id uuid not null references erp_products(id),
  qty numeric(14,3) not null check (qty > 0),
  qty_shipped numeric(14,3) not null default 0,
  unit_price numeric(14,2) not null default 0
);

-- ──────────────────────────────────────────────
-- 5. ESTOQUE (kardex) — logística
-- ──────────────────────────────────────────────
create table if not exists erp_stock_moves (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references erp_products(id),
  warehouse_id uuid not null references erp_warehouses(id),
  type text not null check (type in (
    'entrada_compra','saida_venda','ajuste_entrada','ajuste_saida',
    'consumo_producao','producao_acabado',
    'transferencia_saida','transferencia_entrada'
  )),
  qty numeric(14,3) not null check (qty > 0),
  unit_cost numeric(14,2) not null default 0,
  ref_type text,
  ref_id uuid,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace view erp_stock_balance as
select
  product_id,
  warehouse_id,
  sum(case
    when type in ('entrada_compra','ajuste_entrada','producao_acabado','transferencia_entrada') then qty
    when type in ('saida_venda','ajuste_saida','consumo_producao','transferencia_saida') then -qty
    else 0
  end) as qty_on_hand
from erp_stock_moves
group by product_id, warehouse_id;

-- ──────────────────────────────────────────────
-- 6. PRODUÇÃO (fábrica) — estrutura de produto (BOM)
-- ──────────────────────────────────────────────
create table if not exists erp_boms (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references erp_products(id),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists erp_bom_items (
  id uuid primary key default gen_random_uuid(),
  bom_id uuid not null references erp_boms(id) on delete cascade,
  component_id uuid not null references erp_products(id),
  qty_per numeric(14,4) not null check (qty_per > 0)
);

create table if not exists erp_production_orders (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity,
  product_id uuid not null references erp_products(id),
  bom_id uuid not null references erp_boms(id),
  warehouse_id uuid not null references erp_warehouses(id),
  qty_planned numeric(14,3) not null check (qty_planned > 0),
  qty_produced numeric(14,3) not null default 0,
  status text not null default 'planejada'
    check (status in ('planejada','em_producao','concluida','cancelada')),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

-- ──────────────────────────────────────────────
-- 7. CONTÁBIL
-- ──────────────────────────────────────────────
create table if not exists erp_chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  type text not null check (type in ('ativo','passivo','patrimonio_liquido','receita','despesa')),
  parent_id uuid references erp_chart_of_accounts(id),
  active boolean not null default true
);

create table if not exists erp_journal_entries (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity,
  entry_date date not null default current_date,
  description text not null,
  ref_type text,
  ref_id uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists erp_journal_entry_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references erp_journal_entries(id) on delete cascade,
  account_id uuid not null references erp_chart_of_accounts(id),
  debit numeric(14,2) not null default 0 check (debit >= 0),
  credit numeric(14,2) not null default 0 check (credit >= 0),
  description text,
  check (not (debit > 0 and credit > 0))
);

-- Garante que todo lançamento fecha em zero (débito = crédito) ao
-- final da transação que gravou as linhas.
create or replace function erp_check_journal_balance()
returns trigger language plpgsql as $$
declare
  v_entry_id uuid;
  v_diff numeric;
begin
  v_entry_id := coalesce(new.journal_entry_id, old.journal_entry_id);
  select coalesce(sum(debit),0) - coalesce(sum(credit),0) into v_diff
  from erp_journal_entry_lines where journal_entry_id = v_entry_id;
  if v_diff <> 0 then
    raise exception 'Lançamento % não está balanceado (diferença: %)', v_entry_id, v_diff;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_erp_check_journal_balance on erp_journal_entry_lines;
create constraint trigger trg_erp_check_journal_balance
after insert or update or delete on erp_journal_entry_lines
deferrable initially deferred
for each row execute function erp_check_journal_balance();

-- ──────────────────────────────────────────────
-- 8. FUNÇÕES TRANSACIONAIS (RPC)
--    Garantem consistência entre pedido/produção e o kardex de estoque.
-- ──────────────────────────────────────────────

-- Recebimento de item de pedido de compra -> gera entrada de estoque
create or replace function erp_receive_purchase_order_item(p_item_id uuid, p_qty numeric)
returns void language plpgsql security definer as $$
declare
  it erp_purchase_order_items%rowtype;
  po erp_purchase_orders%rowtype;
  v_status text;
begin
  if not erp_is_active_user() then raise exception 'Sem permissão'; end if;
  if p_qty <= 0 then raise exception 'Quantidade inválida'; end if;

  select * into it from erp_purchase_order_items where id = p_item_id for update;
  if not found then raise exception 'Item de pedido não encontrado'; end if;
  select * into po from erp_purchase_orders where id = it.purchase_order_id;
  if it.qty_received + p_qty > it.qty then
    raise exception 'Quantidade recebida excede o pedido (restam %)', it.qty - it.qty_received;
  end if;

  insert into erp_stock_moves(product_id, warehouse_id, type, qty, unit_cost, ref_type, ref_id, created_by)
  values (it.product_id, po.warehouse_id, 'entrada_compra', p_qty, it.unit_price, 'purchase_order', po.id, auth.uid());

  update erp_purchase_order_items set qty_received = qty_received + p_qty where id = p_item_id;

  select case when sum(qty_received) >= sum(qty) then 'recebido' else 'recebido_parcial' end
  into v_status from erp_purchase_order_items where purchase_order_id = po.id;

  update erp_purchase_orders set status = v_status where id = po.id;
end;
$$;

-- Expedição de item de pedido de venda -> gera saída de estoque (logística)
create or replace function erp_ship_sales_order_item(p_item_id uuid, p_qty numeric)
returns void language plpgsql security definer as $$
declare
  it erp_sales_order_items%rowtype;
  so erp_sales_orders%rowtype;
  v_balance numeric;
  v_status text;
begin
  if not erp_is_active_user() then raise exception 'Sem permissão'; end if;
  if p_qty <= 0 then raise exception 'Quantidade inválida'; end if;

  select * into it from erp_sales_order_items where id = p_item_id for update;
  if not found then raise exception 'Item de pedido não encontrado'; end if;
  select * into so from erp_sales_orders where id = it.sales_order_id;
  if it.qty_shipped + p_qty > it.qty then
    raise exception 'Quantidade expedida excede o pedido (restam %)', it.qty - it.qty_shipped;
  end if;

  select coalesce(qty_on_hand,0) into v_balance from erp_stock_balance
  where product_id = it.product_id and warehouse_id = so.warehouse_id;
  if coalesce(v_balance,0) < p_qty then
    raise exception 'Estoque insuficiente para expedição (saldo: %)', coalesce(v_balance,0);
  end if;

  insert into erp_stock_moves(product_id, warehouse_id, type, qty, unit_cost, ref_type, ref_id, created_by)
  values (it.product_id, so.warehouse_id, 'saida_venda', p_qty, it.unit_price, 'sales_order', so.id, auth.uid());

  update erp_sales_order_items set qty_shipped = qty_shipped + p_qty where id = p_item_id;

  select case when sum(qty_shipped) >= sum(qty) then 'expedido' else 'expedido_parcial' end
  into v_status from erp_sales_order_items where sales_order_id = so.id;

  update erp_sales_orders set status = v_status where id = so.id;
end;
$$;

-- Apontamento de produção -> consome componentes da BOM e gera o
-- produto acabado no estoque
create or replace function erp_finish_production_order(p_order_id uuid, p_qty numeric)
returns void language plpgsql security definer as $$
declare
  o erp_production_orders%rowtype;
  b record;
  v_new_total numeric;
begin
  if not erp_is_active_user() then raise exception 'Sem permissão'; end if;
  if p_qty <= 0 then raise exception 'Quantidade inválida'; end if;

  select * into o from erp_production_orders where id = p_order_id for update;
  if not found then raise exception 'Ordem de produção não encontrada'; end if;
  if o.status = 'concluida' or o.status = 'cancelada' then
    raise exception 'Ordem já finalizada';
  end if;
  v_new_total := o.qty_produced + p_qty;
  if v_new_total > o.qty_planned then
    raise exception 'Quantidade excede o planejado (restam %)', o.qty_planned - o.qty_produced;
  end if;

  for b in select * from erp_bom_items where bom_id = o.bom_id loop
    insert into erp_stock_moves(product_id, warehouse_id, type, qty, ref_type, ref_id, notes, created_by)
    values (b.component_id, o.warehouse_id, 'consumo_producao', b.qty_per * p_qty, 'production_order', o.id, 'Consumo automático (OP)', auth.uid());
  end loop;

  insert into erp_stock_moves(product_id, warehouse_id, type, qty, ref_type, ref_id, notes, created_by)
  values (o.product_id, o.warehouse_id, 'producao_acabado', p_qty, 'production_order', o.id, 'Apontamento de produção', auth.uid());

  update erp_production_orders
  set qty_produced = v_new_total,
      status = case when v_new_total >= qty_planned then 'concluida' else 'em_producao' end,
      started_at = coalesce(started_at, now()),
      finished_at = case when v_new_total >= qty_planned then now() else finished_at end
  where id = p_order_id;
end;
$$;

-- ──────────────────────────────────────────────
-- 9. ROW LEVEL SECURITY
--    Regra geral: qualquer usuário ativo do portal pode ler e lançar
--    operações do ERP; exclusão e cadastros contábeis ficam restritos
--    a admin/líder.
-- ──────────────────────────────────────────────
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'erp_products','erp_partners','erp_warehouses','erp_carriers',
    'erp_purchase_orders','erp_purchase_order_items',
    'erp_sales_orders','erp_sales_order_items',
    'erp_stock_moves',
    'erp_boms','erp_bom_items','erp_production_orders',
    'erp_chart_of_accounts','erp_journal_entries','erp_journal_entry_lines'
  ]) loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Leitura: qualquer usuário ativo
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'erp_products','erp_partners','erp_warehouses','erp_carriers',
    'erp_purchase_orders','erp_purchase_order_items',
    'erp_sales_orders','erp_sales_order_items',
    'erp_stock_moves',
    'erp_boms','erp_bom_items','erp_production_orders',
    'erp_chart_of_accounts','erp_journal_entries','erp_journal_entry_lines'
  ]) loop
    execute format('drop policy if exists erp_select on %I', t);
    execute format('create policy erp_select on %I for select using (erp_is_active_user())', t);
  end loop;
end $$;

-- Cadastros e operações do dia a dia: inserir/atualizar liberado a
-- qualquer usuário ativo; excluir restrito a admin/líder.
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'erp_products','erp_partners','erp_warehouses','erp_carriers',
    'erp_purchase_orders','erp_purchase_order_items',
    'erp_sales_orders','erp_sales_order_items',
    'erp_boms','erp_bom_items','erp_production_orders'
  ]) loop
    execute format('drop policy if exists erp_insert on %I', t);
    execute format('create policy erp_insert on %I for insert with check (erp_is_active_user())', t);
    execute format('drop policy if exists erp_update on %I', t);
    execute format('create policy erp_update on %I for update using (erp_is_active_user()) with check (erp_is_active_user())', t);
    execute format('drop policy if exists erp_delete on %I', t);
    execute format('create policy erp_delete on %I for delete using (erp_is_manager())', t);
  end loop;
end $$;

-- Estoque: os moves normais são criados via RPC (security definer),
-- mas liberamos insert manual (ajustes) para usuários ativos e delete
-- apenas para admin/líder (correção de lançamento errado).
drop policy if exists erp_insert on erp_stock_moves;
create policy erp_insert on erp_stock_moves for insert with check (erp_is_active_user());
drop policy if exists erp_delete on erp_stock_moves;
create policy erp_delete on erp_stock_moves for delete using (erp_is_manager());

-- Contábil: plano de contas e lançamentos só podem ser escritos por
-- admin/líder (papel financeiro).
do $$
declare
  t text;
begin
  for t in select unnest(array['erp_chart_of_accounts','erp_journal_entries','erp_journal_entry_lines']) loop
    execute format('drop policy if exists erp_insert on %I', t);
    execute format('create policy erp_insert on %I for insert with check (erp_is_manager())', t);
    execute format('drop policy if exists erp_update on %I', t);
    execute format('create policy erp_update on %I for update using (erp_is_manager()) with check (erp_is_manager())', t);
    execute format('drop policy if exists erp_delete on %I', t);
    execute format('create policy erp_delete on %I for delete using (erp_is_manager())', t);
  end loop;
end $$;

-- ──────────────────────────────────────────────
-- 10. PLANO DE CONTAS PADRÃO (seed opcional)
-- ──────────────────────────────────────────────
insert into erp_chart_of_accounts (code, name, type) values
  ('1', 'ATIVO', 'ativo'),
  ('1.1', 'Ativo Circulante', 'ativo'),
  ('1.1.01', 'Caixa e Bancos', 'ativo'),
  ('1.1.02', 'Contas a Receber', 'ativo'),
  ('1.1.03', 'Estoques', 'ativo'),
  ('2', 'PASSIVO', 'passivo'),
  ('2.1', 'Passivo Circulante', 'passivo'),
  ('2.1.01', 'Fornecedores a Pagar', 'passivo'),
  ('2.1.02', 'Impostos a Recolher', 'passivo'),
  ('3', 'PATRIMÔNIO LÍQUIDO', 'patrimonio_liquido'),
  ('3.1', 'Capital Social', 'patrimonio_liquido'),
  ('4', 'RECEITAS', 'receita'),
  ('4.1', 'Receita de Vendas', 'receita'),
  ('5', 'DESPESAS', 'despesa'),
  ('5.1', 'Custo dos Produtos Vendidos', 'despesa'),
  ('5.2', 'Despesas Operacionais', 'despesa'),
  ('5.3', 'Despesas com Logística', 'despesa')
on conflict (code) do nothing;

-- ══════════════════════════════════════════════════════════════════
-- Fim do schema. Depois de rodar este arquivo, adicione o tile do
-- Nexus ERP no portal (index.html) — veja erp/README.md.
-- ══════════════════════════════════════════════════════════════════
