
-- 1) Snapshot table
CREATE TABLE public.ranking_position_state (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  previous_position INT,
  current_position INT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.ranking_position_state TO authenticated;
GRANT ALL ON public.ranking_position_state TO service_role;

ALTER TABLE public.ranking_position_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated can read ranking state"
ON public.ranking_position_state FOR SELECT
TO authenticated
USING (true);

-- 2) Refresh function: only updates rows whose position actually changed
CREATE OR REPLACE FUNCTION public.refresh_ranking_state()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_existing INT;
BEGIN
  FOR v_rec IN
    SELECT out_user_id AS user_id, out_position AS position
    FROM public.get_ranking(NULL, NULL, FALSE)
  LOOP
    SELECT current_position INTO v_existing
    FROM public.ranking_position_state
    WHERE user_id = v_rec.user_id;

    IF v_existing IS NULL THEN
      INSERT INTO public.ranking_position_state (user_id, previous_position, current_position)
      VALUES (v_rec.user_id, v_rec.position, v_rec.position);
    ELSIF v_existing IS DISTINCT FROM v_rec.position THEN
      UPDATE public.ranking_position_state
      SET previous_position = v_existing,
          current_position = v_rec.position,
          updated_at = now()
      WHERE user_id = v_rec.user_id;
    END IF;
  END LOOP;
END;
$$;

-- 3) New RPC returning ranking + change (only meaningful for general ranking)
CREATE OR REPLACE FUNCTION public.get_ranking_with_change(p_group_id uuid DEFAULT NULL)
RETURNS TABLE(
  out_user_id uuid,
  out_name text,
  out_total_points bigint,
  out_exact_count bigint,
  out_partial_count bigint,
  out_negative_count bigint,
  out_missed_count bigint,
  out_position integer,
  out_position_change integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.out_user_id,
    r.out_name,
    r.out_total_points,
    r.out_exact_count,
    r.out_partial_count,
    r.out_negative_count,
    r.out_missed_count,
    r.out_position,
    CASE
      WHEN s.previous_position IS NULL THEN NULL
      ELSE (s.previous_position - r.out_position)
    END AS out_position_change
  FROM public.get_ranking(NULL, p_group_id, FALSE) r
  LEFT JOIN public.ranking_position_state s ON s.user_id = r.out_user_id;
$$;

-- 4) Wire refresh into admin score-affecting actions
CREATE OR REPLACE FUNCTION public.admin_adjust_score(p_match_id uuid, p_field text, p_delta integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_home INT;
  v_away INT;
  v_is_started BOOLEAN;
  v_is_finished BOOLEAN;
  v_new_home INT;
  v_new_away INT;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  IF p_field NOT IN ('home_score', 'away_score') THEN
    RAISE EXCEPTION 'Invalid field: %', p_field;
  END IF;

  SELECT home_score, away_score, is_started, is_finished
  INTO v_home, v_away, v_is_started, v_is_finished
  FROM public.matches WHERE id = p_match_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Match not found';
  END IF;

  v_new_home := COALESCE(v_home, 0);
  v_new_away := COALESCE(v_away, 0);

  IF p_field = 'home_score' THEN
    v_new_home := GREATEST(0, COALESCE(v_home, 0) + p_delta);
  ELSE
    v_new_away := GREATEST(0, COALESCE(v_away, 0) + p_delta);
  END IF;

  UPDATE public.matches
  SET home_score = v_new_home,
      away_score = v_new_away
  WHERE id = p_match_id;

  IF v_is_started AND NOT v_is_finished THEN
    PERFORM public.calculate_live_scores(p_match_id);
  ELSIF v_is_finished THEN
    PERFORM public.calculate_match_scores(p_match_id);
  END IF;

  PERFORM public.refresh_ranking_state();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_start_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;
  UPDATE public.matches
    SET is_started = true,
        home_score = COALESCE(home_score, 0),
        away_score = COALESCE(away_score, 0)
    WHERE id = p_match_id;
  PERFORM public.calculate_live_scores(p_match_id);
  PERFORM public.refresh_ranking_state();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_finish_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_home INT; v_away INT;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;
  SELECT home_score, away_score INTO v_home, v_away FROM public.matches WHERE id = p_match_id;
  IF v_home IS NULL OR v_away IS NULL THEN
    RAISE EXCEPTION 'Match score must be set before finishing';
  END IF;
  UPDATE public.matches SET is_finished = true WHERE id = p_match_id;
  PERFORM public.calculate_match_scores(p_match_id);
  PERFORM public.refresh_ranking_state();
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_restart_match(p_match_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;
  DELETE FROM public.scores WHERE match_id = p_match_id;
  UPDATE public.matches
    SET is_started = false, is_finished = false, home_score = NULL, away_score = NULL
    WHERE id = p_match_id;
  PERFORM public.refresh_ranking_state();
END;
$function$;

-- 5) Seed snapshot with current ranking so first read has baseline
SELECT public.refresh_ranking_state();
