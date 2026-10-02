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
