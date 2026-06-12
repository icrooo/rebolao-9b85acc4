
CREATE OR REPLACE FUNCTION public.snapshot_predictions_for_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Allow when invoked by pg_cron (no auth.uid); block non-admin authenticated users
  IF auth.uid() IS NOT NULL AND NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  INSERT INTO public.prediction_snapshots (
    match_id, prediction_id, user_id, name, email,
    home_team, away_team, home_score_pred, away_score_pred, last_prediction_at
  )
  SELECT m.id, p.id, p.user_id, pr.name, pr.email,
         m.home_team, m.away_team, p.home_score_pred, p.away_score_pred, p.updated_at
  FROM public.matches m
  JOIN public.predictions p ON p.match_id = m.id
  JOIN public.profiles pr ON pr.user_id = p.user_id
  WHERE m.id = p_match_id
  ON CONFLICT (match_id, user_id) DO NOTHING;
END;
$function$;
