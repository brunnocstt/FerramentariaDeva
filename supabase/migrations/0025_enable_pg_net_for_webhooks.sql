-- Habilita a extensão pg_net (Async HTTP), pré-requisito pra qualquer chamada HTTP feita de
-- dentro do Postgres (net.http_post/net.http_get). Este projeto foi criado via API/MCP em vez
-- do fluxo padrão do Dashboard, então não recebeu esse provisionamento automático.
create extension if not exists pg_net with schema extensions;
