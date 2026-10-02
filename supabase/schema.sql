-- =====================================================================
-- Budget Tracker App — Supabase schema v1
-- Paste into Supabase: SQL Editor -> New query -> Run.
-- Safe to read top to bottom; matches section 5a of the spec.
-- Money is stored in whole cents. Weeks start on Tuesday (payday).
-- =====================================================================

-- ---------- Helpers ---------------------------------------------------

-- Keeps updated_at fresh. If the app already set updated_at (offline edit
-- being synced), that value is kept so last-write-wins stays accurate.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at := now();
  end if;
  return new;
end $$;

-- The Tuesday that starts the budget week containing a given date.
create or replace function public.week_start_of(d date)
returns date language sql immutable as $$
  select d - ((extract(isodow from d)::int + 5) % 7)
$$;

-- ---------- Budget setup ---------------------------------------------

create table public.category_group (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,                       -- Needs, Wants, Savings
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.category (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  group_id    uuid not null references public.category_group(id),
  name        text not null,
  icon        text,
  archived    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.budget_config (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null default auth.uid() references auth.users on delete cascade,
  weekly_amount_cents  int  not null check (weekly_amount_cents > 0),
  effective_from       date not null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);

create table public.budget_split (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  config_id   uuid not null references public.budget_config(id) on delete cascade,
  group_id    uuid not null references public.category_group(id),
  percent     numeric(5,2) not null check (percent between 0 and 100),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (config_id, group_id)
);

-- ---------- Day-to-day -----------------------------------------------

create table public.expense (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  amount_cents  int  not null check (amount_cents > 0),
  category_id   uuid not null references public.category(id),
  spent_on      date not null default current_date,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table public.income_source (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  name              text not null,
  tax_rate_percent  numeric(5,2) not null default 0 check (tax_rate_percent between 0 and 100),
  is_side_income    boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create table public.income (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null default auth.uid() references auth.users on delete cascade,
  source_id            uuid not null references public.income_source(id),
  amount_cents         int  not null check (amount_cents > 0),
  received_on          date not null default current_date,
  tax_set_aside_cents  int  not null default 0 check (tax_set_aside_cents >= 0),  -- locked in at entry
  note                 text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);

-- ---------- Weekly allocation ----------------------------------------

create table public.account (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,
  type        text not null check (type in ('bank','investment','wallet','super','other')),
  purpose     text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.allocation (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  week_start  date not null check (extract(isodow from week_start) = 2),  -- must be a Tuesday
  config_id   uuid not null references public.budget_config(id),
  status      text not null default 'open' check (status in ('open','done')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (user_id, week_start)
);

create table public.allocation_line (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  allocation_id  uuid not null references public.allocation(id) on delete cascade,
  account_id     uuid not null references public.account(id),
  group_id       uuid references public.category_group(id),
  planned_cents  int  not null check (planned_cents >= 0),
  done           boolean not null default false,
  done_at        timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- ---------- Savings jars ---------------------------------------------

create table public.jar (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  name          text not null,
  target_cents  int check (target_cents is null or target_cents > 0),
  target_date   date,
  archived      boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table public.jar_contribution (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references auth.users on delete cascade,
  jar_id              uuid not null references public.jar(id),
  amount_cents        int  not null check (amount_cents > 0),
  source              text not null check (source in ('residual','allocation','other')),
  allocation_line_id  uuid references public.allocation_line(id),
  contributed_on      date not null default current_date,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);

-- ---------- Triggers, indexes, security (applied to every table) -----

do $$
declare t text;
begin
  foreach t in array array[
    'category_group','category','budget_config','budget_split',
    'expense','income_source','income',
    'account','allocation','allocation_line',
    'jar','jar_contribution'
  ] loop
    -- updated_at trigger
    execute format(
      'create trigger %1$s_touch before update on public.%1$s
         for each row execute function public.touch_updated_at()', t);

    -- fast "what changed since X" lookups for sync
    execute format(
      'create index %1$s_sync_idx on public.%1$s (user_id, updated_at)', t);

    -- row-level security: you only ever see and change your own rows
    execute format('alter table public.%1$s enable row level security', t);
    execute format(
      'create policy "own rows" on public.%1$s for all to authenticated
         using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

create index expense_day_idx on public.expense (user_id, spent_on);
create index income_day_idx  on public.income  (user_id, received_on);

-- ---------- Worked-out values ----------------------------------------

-- Residual per week: income (after tax set-aside) above the weekly budget,
-- minus whatever has already been moved from residual into jars.
create or replace view public.weekly_residual
with (security_invoker = true) as
with inc as (
  select user_id,
         public.week_start_of(received_on) as week_start,
         sum(amount_cents - tax_set_aside_cents) as net_income_cents
  from public.income
  where deleted_at is null
  group by 1, 2
),
used as (
  select user_id,
         public.week_start_of(contributed_on) as week_start,
         sum(amount_cents) as to_jars_cents
  from public.jar_contribution
  where deleted_at is null and source = 'residual'
  group by 1, 2
)
select i.user_id,
       i.week_start,
       i.net_income_cents,
       b.weekly_amount_cents,
       greatest(i.net_income_cents - coalesce(b.weekly_amount_cents, 0), 0) as residual_cents,
       coalesce(u.to_jars_cents, 0) as moved_to_jars_cents,
       greatest(i.net_income_cents - coalesce(b.weekly_amount_cents, 0), 0)
         - coalesce(u.to_jars_cents, 0) as residual_left_cents
from inc i
left join lateral (
  select weekly_amount_cents
  from public.budget_config bc
  where bc.user_id = i.user_id
    and bc.deleted_at is null
    and bc.effective_from <= i.week_start
  order by bc.effective_from desc
  limit 1
) b on true
left join used u on u.user_id = i.user_id and u.week_start = i.week_start;

-- ---------- Starter data ---------------------------------------------
-- The app calls this once after first sign-in:
--   supabase.rpc('seed_defaults')
-- Does nothing if the user already has groups.

create or replace function public.seed_defaults()
returns void language plpgsql security invoker as $$
declare
  g_needs uuid; g_wants uuid; g_save uuid; cfg uuid;
begin
  if exists (select 1 from public.category_group where user_id = auth.uid()) then
    return;
  end if;

  insert into public.category_group (name, sort_order) values ('Needs', 1)   returning id into g_needs;
  insert into public.category_group (name, sort_order) values ('Wants', 2)   returning id into g_wants;
  insert into public.category_group (name, sort_order) values ('Savings', 3) returning id into g_save;

  insert into public.category (group_id, name) values
    (g_needs, 'Rent'), (g_needs, 'Groceries'), (g_needs, 'Transport'), (g_needs, 'Bills'),
    (g_wants, 'Eating out'), (g_wants, 'Coffee'), (g_wants, 'Entertainment'), (g_wants, 'Shopping'),
    (g_save,  'Investing'), (g_save, 'Emergency fund');

  insert into public.budget_config (weekly_amount_cents, effective_from)
    values (60000, public.week_start_of(current_date)) returning id into cfg;

  insert into public.budget_split (config_id, group_id, percent) values
    (cfg, g_needs, 50), (cfg, g_wants, 20), (cfg, g_save, 30);

  insert into public.account (name, type, purpose) values
    ('Com Bank',      'bank',       'Rent'),
    ('Raiz',          'investment', null),
    ('ANZ',           'bank',       null),
    ('ANZ Plus',      'bank',       null),
    ('ING',           'bank',       'Joint account'),
    ('Apple Wallet',  'wallet',     null),
    ('Savings',       'bank',       'Emergency fund'),
    ('Vanguard',      'investment', 'Shares / ETF'),
    ('Pearler',       'investment', 'S&P 500 (funded via Com Bank)');

  insert into public.jar (name) values ('Vacation'), ('Bike in Nepal'), ('New phone');
end $$;


-- Budget Tracker — fixed expenses (run once in Supabase SQL Editor)
-- Rent, bills and other regular costs that log themselves on their due date.

create table if not exists public.recurring_expense (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  name          text not null,
  amount_cents  int  not null check (amount_cents > 0),
  category_id   uuid not null references public.category(id),
  frequency     text not null check (frequency in ('weekly','fortnightly','monthly')),
  start_date    date not null,
  next_due      date not null,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

drop trigger if exists recurring_expense_touch on public.recurring_expense;
create trigger recurring_expense_touch before update on public.recurring_expense
  for each row execute function public.touch_updated_at();
create index if not exists recurring_expense_sync_idx on public.recurring_expense (user_id, updated_at);
alter table public.recurring_expense enable row level security;
drop policy if exists "own rows" on public.recurring_expense;
create policy "own rows" on public.recurring_expense for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Each logged expense remembers which fixed expense created it,
-- and the same fixed expense can't log twice on one day.
alter table public.expense
  add column if not exists recurring_id uuid references public.recurring_expense(id);
create unique index if not exists expense_recurring_once
  on public.expense (recurring_id, spent_on)
  where recurring_id is not null and deleted_at is null;

-- Logs every fixed expense that has fallen due up to p_today (the phone's
-- local date), then moves each one's next date on. Safe to call from several
-- devices at once. Returns how many expenses were logged.
create or replace function public.post_due_fixed_expenses(p_today date)
returns int language plpgsql security invoker as $$
declare
  r      record;
  due    date;
  today  date := least(p_today, current_date + 1);
  posted int  := 0;
  guard  int;
begin
  for r in
    select * from public.recurring_expense
    where user_id = auth.uid() and active and deleted_at is null and next_due <= today
    for update skip locked
  loop
    due := r.next_due;
    guard := 0;
    while due <= today and guard < 400 loop
      insert into public.expense (amount_cents, category_id, spent_on, note, recurring_id)
      values (r.amount_cents, r.category_id, due, r.name, r.id)
      on conflict do nothing;
      posted := posted + 1;
      guard := guard + 1;
      due := case r.frequency
        when 'weekly' then due + 7
        when 'fortnightly' then due + 14
        -- monthly: count from the start date so the 31st stays the 31st (or month end)
        else (r.start_date + make_interval(months =>
               (extract(year from due)::int * 12 + extract(month from due)::int)
             - (extract(year from r.start_date)::int * 12 + extract(month from r.start_date)::int)
             + 1))::date
      end;
    end loop;
    update public.recurring_expense set next_due = due where id = r.id;
  end loop;
  return posted;
end $$;
