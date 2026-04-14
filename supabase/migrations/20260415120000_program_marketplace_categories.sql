-- Marketplace: categories, listing visibility, seed programs (idempotent for mp-* ids).

-- ---------------------------------------------------------------------------
-- Categories (discover tab filters)
-- ---------------------------------------------------------------------------
create table if not exists public.catalog_categories (
  slug text primary key,
  title text not null,
  subtitle text not null default '',
  sort_order int not null default 0,
  icon_sf_symbol text not null default 'figure.strengthtraining.traditional'
);

comment on table public.catalog_categories is 'Browse groupings for catalog programs in the app marketplace.';

insert into public.catalog_categories (slug, title, subtitle, sort_order, icon_sf_symbol) values
  ('featured', 'Featured', 'Curated picks', 0, 'star.fill'),
  ('strength', 'Strength', 'Heavy compounds & progression', 10, 'dumbbell.fill'),
  ('hypertrophy', 'Hypertrophy', 'Volume & muscle building', 20, 'figure.strengthtraining.functional'),
  ('athletic', 'Athletic', 'Performance & conditioning', 30, 'figure.run'),
  ('beginner', 'Beginner', 'Simple full-body friendly', 40, 'leaf.fill'),
  ('specialty', 'Specialty', 'Arms, abs, and focused splits', 50, 'sparkles')
on conflict (slug) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  sort_order = excluded.sort_order,
  icon_sf_symbol = excluded.icon_sf_symbol;

-- ---------------------------------------------------------------------------
-- Catalog programs: category + listing (draft / pending_review for future admin + submissions)
-- ---------------------------------------------------------------------------
alter table public.catalog_programs
  add column if not exists category_slug text references public.catalog_categories (slug) on update cascade on delete restrict;

alter table public.catalog_programs
  add column if not exists listing_status text not null default 'live';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'catalog_programs_listing_status_check'
  ) then
    alter table public.catalog_programs
      add constraint catalog_programs_listing_status_check
      check (listing_status in ('live', 'draft', 'pending_review'));
  end if;
end $$;

comment on column public.catalog_programs.category_slug is 'Marketplace section.';
comment on column public.catalog_programs.listing_status is 'live = app marketplace; draft = admin only; pending_review = user submission.';

update public.catalog_programs
set category_slug = coalesce(category_slug, 'strength')
where category_slug is null;

alter table public.catalog_programs
  alter column category_slug set not null;

alter table public.catalog_programs
  alter column category_slug set default 'strength';

create index if not exists catalog_programs_category_listing_idx
  on public.catalog_programs (category_slug, listing_status);

update public.catalog_programs set category_slug = 'featured' where id = 'program-1';
update public.catalog_programs set category_slug = 'hypertrophy' where id = 'program-2';
update public.catalog_programs set category_slug = 'strength' where id = 'program-3';
update public.catalog_programs set category_slug = 'athletic' where id = 'program-4';
update public.catalog_programs set category_slug = 'beginner' where id = 'program-5';
update public.catalog_programs set category_slug = 'specialty' where id = 'program-6';
update public.catalog_programs set category_slug = 'specialty' where id like 'user-%' and id is not null;

-- ---------------------------------------------------------------------------
-- RLS: categories readable like catalog
-- ---------------------------------------------------------------------------
alter table public.catalog_categories enable row level security;

drop policy if exists "catalog_categories_read" on public.catalog_categories;
create policy "catalog_categories_read"
  on public.catalog_categories for select
  to authenticated, anon
  using (true);

-- ---------------------------------------------------------------------------
-- Re-seed marketplace programs (mp-*) — delete first for idempotent migrations
-- ---------------------------------------------------------------------------
delete from public.catalog_programs where id like 'mp-%';

insert into public.catalog_programs (id, name, subtitle, period, date_range, color, is_user_created, category_slug, listing_status)
values
  ('mp-upper-power', 'Upper Power', 'Heavy upper — bench & row focus', '', '', '#6366F1', false, 'strength', 'live'),
  ('mp-lower-power', 'Lower Power', 'Squat & hinge patterns', '', '', '#8B5CF6', false, 'strength', 'live'),
  ('mp-push-pull-legs', 'Classic PPL', '6-day push / pull / legs rotation', '', '', '#EC4899', false, 'hypertrophy', 'live'),
  ('mp-upper-lower-hypertrophy', 'Upper / Lower Hypertrophy', '4-day split for size', '', '', '#F97316', false, 'hypertrophy', 'live'),
  ('mp-full-body-3', 'Full Body 3×', 'Three efficient total-body sessions', '', '', '#22C55E', false, 'beginner', 'live'),
  ('mp-glute-legs', 'Glute & Legs', 'Quad and posterior chain emphasis', '', '', '#14B8A6', false, 'hypertrophy', 'live'),
  ('mp-arm-focus', 'Arm Builder', 'Biceps & triceps specialization', '', '', '#EAB308', false, 'specialty', 'live'),
  ('mp-conditioning-circuit', 'Conditioning Circuit', 'Full-body machine circuit', '', '', '#0EA5E9', false, 'athletic', 'live'),
  ('mp-minimal-equipment', 'Minimal Equipment', 'Dumbbells & bodyweight friendly', '', '', '#A855F7', false, 'beginner', 'live'),
  ('mp-shoulder-health', 'Shoulder Friendly Upper', 'Press variations & pulls', '', '', '#64748B', false, 'athletic', 'live'),
  ('mp-back-thickness', 'Back Thickness', 'Rows and vertical pulls', '', '', '#334155', false, 'strength', 'live'),
  ('mp-press-specialist', 'Press Specialist', 'Flat & incline pressing block', '', '', '#F43F5E', false, 'hypertrophy', 'live'),
  ('mp-lower-volume', 'Lower Hypertrophy', 'Leg press & isolation finishers', '', '', '#84CC16', false, 'hypertrophy', 'live'),
  ('mp-athletic-total', 'Athletic Total Body', 'Balanced power & conditioning', '', '', '#06B6D4', false, 'athletic', 'live'),
  ('mp-starter-split', 'Starter Upper / Lower', 'Two-day repeat for new lifters', '', '', '#10B981', false, 'beginner', 'live'),
  ('mp-deload-reset', 'Deload Week', 'Reduced volume recovery template', '', '', '#94A3B8', false, 'featured', 'live'),
  ('mp-machine-only', 'Machine Only', 'Great for busy commercial gyms', '', '', '#D946EF', false, 'beginner', 'live'),
  ('mp-powerbuilding', 'Powerbuilding Blend', 'Heavy compounds + accessories', '', '', '#EF4444', false, 'strength', 'live');

insert into public.catalog_program_days (program_id, day_index, label) values
  ('mp-upper-power', 0, 'Day 1 – Heavy Upper'),
  ('mp-upper-power', 1, 'Day 2 – Accessories'),
  ('mp-lower-power', 0, 'Day 1 – Squat & hinge'),
  ('mp-lower-power', 1, 'Day 2 – Hamstrings & calves'),
  ('mp-push-pull-legs', 0, 'Push'),
  ('mp-push-pull-legs', 1, 'Pull'),
  ('mp-push-pull-legs', 2, 'Legs'),
  ('mp-upper-lower-hypertrophy', 0, 'Day 1 – Upper volume'),
  ('mp-full-body-3', 0, 'Full body A'),
  ('mp-glute-legs', 0, 'Glute & legs'),
  ('mp-arm-focus', 0, 'Arms'),
  ('mp-conditioning-circuit', 0, 'Circuit'),
  ('mp-minimal-equipment', 0, 'DB total body'),
  ('mp-shoulder-health', 0, 'Shoulder-friendly'),
  ('mp-back-thickness', 0, 'Back'),
  ('mp-press-specialist', 0, 'Pressing'),
  ('mp-lower-volume', 0, 'Leg volume'),
  ('mp-athletic-total', 0, 'Total body power'),
  ('mp-starter-split', 0, 'Upper starter'),
  ('mp-deload-reset', 0, 'Deload'),
  ('mp-machine-only', 0, 'Machines'),
  ('mp-powerbuilding', 0, 'Powerbuilding')
on conflict (program_id, day_index) do update set label = excluded.label;

-- Exercise UUIDs from bundled seed (stable)
insert into public.catalog_day_exercises (program_day_id, exercise_id, sort_order, max_weight, target_sets, superset_group, is_amrap, is_warmup, notes)
select d.id, v.exercise_id, v.sort_order, '', 3, null, null, null, null
from public.catalog_program_days d
join (values
  ('mp-upper-power', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-upper-power', 0, 1, '39aff0b1-4fb7-5884-8b81-72530ae8a8a9'::uuid),
  ('mp-upper-power', 0, 2, '5290bbc5-6e6b-57eb-9a4b-e7ab9e4625b9'::uuid),
  ('mp-upper-power', 0, 3, '93b5c7ec-02eb-5e04-9383-0061255d1d82'::uuid),
  ('mp-upper-power', 1, 0, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-upper-power', 1, 1, '6682a0ea-363a-51ce-8800-a38312024a82'::uuid),
  ('mp-upper-power', 1, 2, 'bb72b23d-7cca-578c-9c9e-f01d5928cf9a'::uuid),
  ('mp-upper-power', 1, 3, 'bdbaff9d-2a84-53ae-8c63-bae383b81857'::uuid),
  ('mp-lower-power', 0, 0, '37e2688a-67c8-58a4-864d-959aa6e89308'::uuid),
  ('mp-lower-power', 0, 1, 'fa690959-d8bb-5e95-a07f-206062786672'::uuid),
  ('mp-lower-power', 0, 2, '6f79f10b-2cb4-5ec7-b732-c92353d1377e'::uuid),
  ('mp-lower-power', 0, 3, 'ae43d5b0-3299-5ecf-832c-23178ac4fb1c'::uuid),
  ('mp-lower-power', 1, 0, '043bec26-8331-5336-a38a-2bf9fe81e17f'::uuid),
  ('mp-lower-power', 1, 1, '96231b75-96ee-5a48-9289-99facdb2b42d'::uuid),
  ('mp-lower-power', 1, 2, '3742940c-7fba-5aab-b956-a88cf988d312'::uuid),
  ('mp-lower-power', 1, 3, 'f703ba89-db43-5975-8bee-157b6fbccb70'::uuid),
  ('mp-push-pull-legs', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-push-pull-legs', 0, 1, '65adac96-47ed-5056-8e47-fb2a93bd0781'::uuid),
  ('mp-push-pull-legs', 0, 2, '5b509ce9-caf5-5ed5-87be-848b9e80414b'::uuid),
  ('mp-push-pull-legs', 0, 3, '60425b23-8f46-5d89-b523-98e9d73e209d'::uuid),
  ('mp-push-pull-legs', 1, 0, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-push-pull-legs', 1, 1, '39aff0b1-4fb7-5884-8b81-72530ae8a8a9'::uuid),
  ('mp-push-pull-legs', 1, 2, '023ce2c7-448a-531f-9bdb-dd813275ce67'::uuid),
  ('mp-push-pull-legs', 1, 3, '96c82045-457c-5982-8ef2-e81881182402'::uuid),
  ('mp-push-pull-legs', 2, 0, '6f79f10b-2cb4-5ec7-b732-c92353d1377e'::uuid),
  ('mp-push-pull-legs', 2, 1, 'fa690959-d8bb-5e95-a07f-206062786672'::uuid),
  ('mp-push-pull-legs', 2, 2, 'ae43d5b0-3299-5ecf-832c-23178ac4fb1c'::uuid),
  ('mp-push-pull-legs', 2, 3, 'ad181cff-1235-5ae3-a433-822e74ddeb0a'::uuid),
  ('mp-upper-lower-hypertrophy', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-upper-lower-hypertrophy', 0, 1, '5290bbc5-6e6b-57eb-9a4b-e7ab9e4625b9'::uuid),
  ('mp-upper-lower-hypertrophy', 0, 2, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-upper-lower-hypertrophy', 0, 3, '6682a0ea-363a-51ce-8800-a38312024a82'::uuid),
  ('mp-upper-lower-hypertrophy', 0, 4, 'bb72b23d-7cca-578c-9c9e-f01d5928cf9a'::uuid),
  ('mp-full-body-3', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-full-body-3', 0, 1, 'fa690959-d8bb-5e95-a07f-206062786672'::uuid),
  ('mp-full-body-3', 0, 2, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-full-body-3', 0, 3, '93b5c7ec-02eb-5e04-9383-0061255d1d82'::uuid),
  ('mp-full-body-3', 0, 4, 'f703ba89-db43-5975-8bee-157b6fbccb70'::uuid),
  ('mp-glute-legs', 0, 0, '6f79f10b-2cb4-5ec7-b732-c92353d1377e'::uuid),
  ('mp-glute-legs', 0, 1, 'fa690959-d8bb-5e95-a07f-206062786672'::uuid),
  ('mp-glute-legs', 0, 2, '043bec26-8331-5336-a38a-2bf9fe81e17f'::uuid),
  ('mp-glute-legs', 0, 3, '3742940c-7fba-5aab-b956-a88cf988d312'::uuid),
  ('mp-glute-legs', 0, 4, '96231b75-96ee-5a48-9289-99facdb2b42d'::uuid),
  ('mp-arm-focus', 0, 0, '96c82045-457c-5982-8ef2-e81881182402'::uuid),
  ('mp-arm-focus', 0, 1, 'e06c416e-994f-516e-984c-46ac44c3ee09'::uuid),
  ('mp-arm-focus', 0, 2, 'bdbaff9d-2a84-53ae-8c63-bae383b81857'::uuid),
  ('mp-arm-focus', 0, 3, '5b509ce9-caf5-5ed5-87be-848b9e80414b'::uuid),
  ('mp-arm-focus', 0, 4, '2825f886-04be-56a0-a985-66602b36e301'::uuid),
  ('mp-conditioning-circuit', 0, 0, 'cff22030-6f41-5000-a127-d92082737d0c'::uuid),
  ('mp-conditioning-circuit', 0, 1, '2b966083-4f4c-5a1d-aa67-69f6e687d686'::uuid),
  ('mp-conditioning-circuit', 0, 2, 'ae43d5b0-3299-5ecf-832c-23178ac4fb1c'::uuid),
  ('mp-conditioning-circuit', 0, 3, '184bd666-1732-58a1-b6e7-c20f9eb5f721'::uuid),
  ('mp-conditioning-circuit', 0, 4, '73db24ca-c306-57df-95e7-c44cbd200be9'::uuid),
  ('mp-minimal-equipment', 0, 0, '92835cdf-3c3e-5908-8cbb-1868e5be830e'::uuid),
  ('mp-minimal-equipment', 0, 1, '65adac96-47ed-5056-8e47-fb2a93bd0781'::uuid),
  ('mp-minimal-equipment', 0, 2, '37e2688a-67c8-58a4-864d-959aa6e89308'::uuid),
  ('mp-minimal-equipment', 0, 3, 'f64667c2-2b94-5829-925c-d0e101373ca8'::uuid),
  ('mp-minimal-equipment', 0, 4, 'fa690959-d8bb-5e95-a07f-206062786672'::uuid),
  ('mp-shoulder-health', 0, 0, 'fbeb728d-5d90-562c-8f7d-a033c2da5c3c'::uuid),
  ('mp-shoulder-health', 0, 1, '023ce2c7-448a-531f-9bdb-dd813275ce67'::uuid),
  ('mp-shoulder-health', 0, 2, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-shoulder-health', 0, 3, 'ac31f60a-aed0-5ad9-8223-6a5cf5105271'::uuid),
  ('mp-shoulder-health', 0, 4, 'fe2b3a5e-670d-5461-886d-ad6997488626'::uuid),
  ('mp-back-thickness', 0, 0, '39aff0b1-4fb7-5884-8b81-72530ae8a8a9'::uuid),
  ('mp-back-thickness', 0, 1, '6fcc3df6-1c49-52bf-a6f4-8097bc46047b'::uuid),
  ('mp-back-thickness', 0, 2, 'd8f42e90-ced5-560a-bb20-28034ede9f28'::uuid),
  ('mp-back-thickness', 0, 3, 'ccd802dc-d01b-58ae-9db4-af50b64dbb8b'::uuid),
  ('mp-back-thickness', 0, 4, 'dfef2de1-7488-5c15-b653-6729b8bd3b87'::uuid),
  ('mp-press-specialist', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-press-specialist', 0, 1, '35266b79-b63f-5bf1-ae06-d420597eef76'::uuid),
  ('mp-press-specialist', 0, 2, 'c2b6ca83-8fd9-5692-83b5-b5ed3ac49f91'::uuid),
  ('mp-press-specialist', 0, 3, 'b97737d1-2a04-51d8-9731-41ddd1709e82'::uuid),
  ('mp-press-specialist', 0, 4, '84eb9c20-7bf2-583a-b96f-f2f2a169afd5'::uuid),
  ('mp-lower-volume', 0, 0, '6f79f10b-2cb4-5ec7-b732-c92353d1377e'::uuid),
  ('mp-lower-volume', 0, 1, 'ae43d5b0-3299-5ecf-832c-23178ac4fb1c'::uuid),
  ('mp-lower-volume', 0, 2, '21bf1fd2-e3fb-5c23-9072-8b44692ad5b4'::uuid),
  ('mp-lower-volume', 0, 3, '57626014-d298-5fb8-9b46-bed21e43471a'::uuid),
  ('mp-lower-volume', 0, 4, '5284c0ae-82ca-536e-bf29-281625c34043'::uuid),
  ('mp-athletic-total', 0, 0, '37e2688a-67c8-58a4-864d-959aa6e89308'::uuid),
  ('mp-athletic-total', 0, 1, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-athletic-total', 0, 2, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-athletic-total', 0, 3, '0a0d0f2f-0560-5b32-9d4e-c50ad9717bde'::uuid),
  ('mp-athletic-total', 0, 4, 'f64667c2-2b94-5829-925c-d0e101373ca8'::uuid),
  ('mp-starter-split', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-starter-split', 0, 1, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-starter-split', 0, 2, '65adac96-47ed-5056-8e47-fb2a93bd0781'::uuid),
  ('mp-starter-split', 0, 3, '6f79f10b-2cb4-5ec7-b732-c92353d1377e'::uuid),
  ('mp-starter-split', 0, 4, 'f703ba89-db43-5975-8bee-157b6fbccb70'::uuid),
  ('mp-deload-reset', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-deload-reset', 0, 1, 'fa690959-d8bb-5e95-a07f-206062786672'::uuid),
  ('mp-deload-reset', 0, 2, 'b5bf19be-16e4-5706-92fa-a047f9f35113'::uuid),
  ('mp-deload-reset', 0, 3, '93b5c7ec-02eb-5e04-9383-0061255d1d82'::uuid),
  ('mp-deload-reset', 0, 4, '0451dfac-9346-57b3-8d7b-5aaa377cb574'::uuid),
  ('mp-machine-only', 0, 0, '184bd666-1732-58a1-b6e7-c20f9eb5f721'::uuid),
  ('mp-machine-only', 0, 1, '73db24ca-c306-57df-95e7-c44cbd200be9'::uuid),
  ('mp-machine-only', 0, 2, '2eee423b-ecb8-508d-87e0-2ff9377bc13c'::uuid),
  ('mp-machine-only', 0, 3, 'ae43d5b0-3299-5ecf-832c-23178ac4fb1c'::uuid),
  ('mp-machine-only', 0, 4, '9ec71266-7cf1-5953-83b9-0d79ddbdc86e'::uuid),
  ('mp-powerbuilding', 0, 0, '3606fe51-8f68-5227-8d83-74f852ebc8e3'::uuid),
  ('mp-powerbuilding', 0, 1, '7b16ec9f-61d3-552c-90c2-2414cf9df11f'::uuid),
  ('mp-powerbuilding', 0, 2, '39aff0b1-4fb7-5884-8b81-72530ae8a8a9'::uuid),
  ('mp-powerbuilding', 0, 3, '6f79f10b-2cb4-5ec7-b732-c92353d1377e'::uuid),
  ('mp-powerbuilding', 0, 4, '65adac96-47ed-5056-8e47-fb2a93bd0781'::uuid)
) as v(program_id, day_index, sort_order, exercise_id)
  on d.program_id = v.program_id and d.day_index = v.day_index
on conflict (program_day_id, sort_order) do update set
  exercise_id = excluded.exercise_id,
  max_weight = excluded.max_weight,
  target_sets = excluded.target_sets;

update public.catalog_release
set version = version + 1,
    notes = 'marketplace categories + mp-* programs',
    published_at = now()
where id = 1;
