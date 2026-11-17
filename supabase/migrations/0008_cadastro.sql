-- =====================================================================
-- BORA — 0008: cadastro em etapas (estilo Uber)
--  Dados pessoais (nome, sobrenome, idioma) -> termos -> forma de pagamento
--  -> localização -> verificação de segurança (CPF etc.) -> emergência.
-- =====================================================================

alter table profiles
  add column if not exists first_name         text,
  add column if not exists last_name          text,
  add column if not exists preferred_language text not null default 'pt-BR'
    check (preferred_language in ('pt-BR', 'en', 'es')),
  add column if not exists terms_accepted_at  timestamptz,
  add column if not exists payment_pref       text
    check (payment_pref in ('pix', 'dinheiro', 'cartao'));

-- Quem já tinha nome completo ganha nome/sobrenome separados
update profiles
   set first_name = split_part(trim(full_name), ' ', 1),
       last_name  = nullif(trim(substr(trim(full_name), length(split_part(trim(full_name), ' ', 1)) + 1)), '')
 where full_name is not null and first_name is null;

-- Quem já terminou o cadastro antes desta versão conta como tendo aceitado os termos
update profiles set terms_accepted_at = created_at where onboarding_done and terms_accepted_at is null;

create or replace function save_basic_profile(p_first_name text, p_last_name text, p_language text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if char_length(trim(coalesce(p_first_name, ''))) < 2 then raise exception 'invalid_first_name'; end if;
  if char_length(trim(coalesce(p_last_name, ''))) < 2 then raise exception 'invalid_last_name'; end if;
  update profiles
     set first_name = trim(p_first_name),
         last_name = trim(p_last_name),
         preferred_language = coalesce(nullif(p_language, ''), 'pt-BR'),
         -- o nome completo só muda enquanto a identidade não foi aprovada
         full_name = case when identity_status in ('pending', 'rejected')
                          then trim(p_first_name) || ' ' || trim(p_last_name) else full_name end
   where id = auth.uid();
end $$;

create or replace function accept_terms() returns void
language sql security definer set search_path = public as $$
  update profiles set terms_accepted_at = coalesce(terms_accepted_at, now()) where id = auth.uid();
$$;

create or replace function set_payment_pref(p_pref text) returns void
language sql security definer set search_path = public as $$
  update profiles set payment_pref = nullif(p_pref, '') where id = auth.uid();
$$;

-- CPF, nascimento e gênero (o nome já vem da etapa de dados pessoais)
create or replace function submit_identity(
  p_cpf text, p_birth_date date, p_gender gender, p_women_only_pref boolean
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_cpf !~ '^\d{11}$' then raise exception 'invalid_cpf'; end if;
  if p_birth_date > (current_date - interval '18 years') then raise exception 'must_be_adult'; end if;

  update profiles
     set cpf = p_cpf, birth_date = p_birth_date, gender = p_gender,
         women_only_pref = (p_gender = 'female' and coalesce(p_women_only_pref, false))
   where id = auth.uid() and identity_status in ('pending', 'rejected');
  if not found then raise exception 'identity_locked'; end if;
exception
  when unique_violation then raise exception 'cpf_already_registered';
end $$;

create or replace function finish_onboarding() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and first_name is not null and last_name is not null)
    then raise exception 'registration_incomplete'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and terms_accepted_at is not null)
    then raise exception 'terms_required'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and cpf is not null)
    then raise exception 'registration_incomplete'; end if;
  if not exists (select 1 from emergency_contacts where user_id = auth.uid())
    then raise exception 'emergency_contact_required'; end if;
  update profiles set onboarding_done = true where id = auth.uid();
end $$;

revoke execute on function save_basic_profile(text, text, text), accept_terms(), set_payment_pref(text),
                           submit_identity(text, date, gender, boolean)
       from public, anon;
grant execute on function save_basic_profile(text, text, text), accept_terms(), set_payment_pref(text),
                          submit_identity(text, date, gender, boolean)
      to authenticated;
