-- Bloco A: correções de segurança
-- 1. Bloquear chamada direta de refresh_ranking_state pelo cliente
REVOKE EXECUTE ON FUNCTION public.refresh_ranking_state() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.refresh_ranking_state() FROM anon;
REVOKE EXECUTE ON FUNCTION public.refresh_ranking_state() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.refresh_ranking_state() TO service_role;

-- 2. Esconder profiles.email do cliente (coluna-nível). Admin lê via RPC admin_get_profiles (SECURITY DEFINER).
REVOKE SELECT (email) ON public.profiles FROM anon;
REVOKE SELECT (email) ON public.profiles FROM authenticated;