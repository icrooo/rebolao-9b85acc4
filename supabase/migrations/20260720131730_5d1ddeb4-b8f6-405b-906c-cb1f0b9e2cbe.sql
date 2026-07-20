-- Revoga acesso anônimo de TODAS as funções SECURITY DEFINER, exceto get_approved_count (usada na tela de login antes de autenticar)
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_approved(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_ranking(date, uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_ranking_with_change(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_user_rank(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_get_profiles() FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_approve_user(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_unapprove_user(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_adjust_score(uuid, text, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_start_match(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_restart_match(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_finish_match(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.calculate_live_scores(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.calculate_match_scores(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.ensure_kickoff_snapshot(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.snapshot_predictions() FROM anon;
REVOKE EXECUTE ON FUNCTION public.snapshot_predictions_for_match(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.schedule_match_snapshot(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.prevent_self_approval() FROM anon;
REVOKE EXECUTE ON FUNCTION public.trg_schedule_match_snapshot() FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_prediction_name() FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM anon;

-- Revoga acesso de usuários autenticados nas funções internas que não devem ser chamadas pelo cliente
-- (has_role/is_approved permanecem executáveis para authenticated pois são usadas em políticas RLS)
REVOKE EXECUTE ON FUNCTION public.calculate_live_scores(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.calculate_match_scores(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.ensure_kickoff_snapshot(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.snapshot_predictions() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.snapshot_predictions_for_match(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.schedule_match_snapshot(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_self_approval() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_schedule_match_snapshot() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.set_prediction_name() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM authenticated;