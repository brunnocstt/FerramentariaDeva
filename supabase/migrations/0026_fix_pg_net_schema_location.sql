-- Garante o schema "net" (convenção padrão da Supabase pra pg_net) e as permissões de uso das
-- funções net.http_get/net.http_post pros papéis do projeto. A tentativa de mover a extensão
-- em si pro schema "net" não pega (a plataforma força pg_net a viver em "extensions"), mas o
-- schema "net" continua existindo com as funções de fato utilizáveis — é o que importa.
create schema if not exists net;
create extension if not exists pg_net with schema net;
grant usage on schema net to postgres, anon, authenticated, service_role;
grant execute on all functions in schema net to postgres, anon, authenticated, service_role;
