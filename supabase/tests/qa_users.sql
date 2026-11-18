-- Cria 3 contas de teste automático com a senha passada em :pw (gerada a cada execução).
-- qa1 = motorista, qa2 = passageira, qa3 = passageiro. O cadastro em si é feito pelo teste, pela API.
\i supabase/tests/qa_cleanup.sql
begin;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
select ('e0000000-0000-4000-8000-00000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'qa' || n || '@bora.dev', extensions.crypt(:'pw', extensions.gen_salt('bf')),
       now(), '{"provider":"email","providers":["email"]}', '{"qa":true}', now(), now(), '', '', '', ''
  from generate_series(1, 3) n;
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, 'email',
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true), now(), now(), now()
  from auth.users u where u.email like 'qa_@bora.dev';
commit;
