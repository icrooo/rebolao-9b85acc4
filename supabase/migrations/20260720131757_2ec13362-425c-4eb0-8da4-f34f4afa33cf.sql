-- Remove default PUBLIC EXECUTE em todas as SECURITY DEFINER; regrant apenas o mínimo necessário
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_approved(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_ranking(date, uuid, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_ranking_with_change(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_rank(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_approved_count() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_get_profiles() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_approve_user(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_unapprove_user(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_adjust_score(uuid, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_start_match(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_restart_match(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_finish_match(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.calculate_live_scores(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.calculate_match_scores(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_kickoff_snapshot(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.snapshot_predictions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.snapshot_predictions_for_match(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.schedule_match_snapshot(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prevent_self_approval() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_schedule_match_snapshot() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_prediction_name() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC;

-- Regrant mínimo necessário
-- Autenticados: funções lidas por policies + funções chamadas pelo app após login
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_approved(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ranking(date, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ranking_with_change(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_rank(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_approved_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_profiles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_unapprove_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_adjust_score(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_start_match(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_restart_match(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_finish_match(uuid) TO authenticated;

-- Anônimo: apenas contagem de aprovados (tela de login)
GRANT EXECUTE ON FUNCTION public.get_approved_count() TO anon;

-- Service role continua com tudo (default), garantimos explicitamente as internas
GRANT EXECUTE ON FUNCTION public.refresh_ranking_state() TO service_role;
GRANT EXECUTE ON FUNCTION public.snapshot_predictions_for_match(uuid) TO service_role;