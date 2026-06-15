
-- ============ 1. Indexes ============
CREATE INDEX IF NOT EXISTS idx_predictions_match_id ON public.predictions (match_id);
CREATE INDEX IF NOT EXISTS idx_matches_datetime ON public.matches (match_datetime);
CREATE INDEX IF NOT EXISTS idx_ufg_group_id ON public.user_friendship_groups (group_id);
CREATE INDEX IF NOT EXISTS idx_profiles_approved ON public.profiles (user_id) WHERE is_approved = true;
CREATE INDEX IF NOT EXISTS idx_scores_match_id ON public.scores (match_id);
CREATE INDEX IF NOT EXISTS idx_scores_user_id ON public.scores (user_id);

-- ============ 2. Ranking cache table ============
CREATE TABLE IF NOT EXISTS public.ranking_cache (
  user_id uuid PRIMARY KEY,
  name text NOT NULL,
  total_points bigint NOT NULL DEFAULT 0,
  exact_count bigint NOT NULL DEFAULT 0,
  partial_count bigint NOT NULL DEFAULT 0,
  negative_count bigint NOT NULL DEFAULT 0,
  missed_count bigint NOT NULL DEFAULT 0,
  position int NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.ranking_cache TO authenticated;
GRANT ALL ON public.ranking_cache TO service_role;

ALTER TABLE public.ranking_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read ranking cache" ON public.ranking_cache;
CREATE POLICY "Authenticated can read ranking cache"
  ON public.ranking_cache
  FOR SELECT
  TO authenticated
  USING (true);

-- ============ 3. refresh_ranking_state: bulk update + populate cache ============
CREATE OR REPLACE FUNCTION public.refresh_ranking_state()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  CREATE TEMP TABLE _rk ON COMMIT DROP AS
    SELECT * FROM public.get_ranking(NULL, NULL, FALSE);

  INSERT INTO public.ranking_position_state (user_id, previous_position, current_position)
  SELECT r.out_user_id, r.out_position, r.out_position FROM _rk r
  ON CONFLICT (user_id) DO UPDATE
    SET previous_position = CASE
          WHEN public.ranking_position_state.current_position IS DISTINCT FROM EXCLUDED.current_position
            THEN public.ranking_position_state.current_position
          ELSE public.ranking_position_state.previous_position
        END,
        current_position = EXCLUDED.current_position,
        updated_at = CASE
          WHEN public.ranking_position_state.current_position IS DISTINCT FROM EXCLUDED.current_position
            THEN now()
          ELSE public.ranking_position_state.updated_at
        END;

  DELETE FROM public.ranking_cache;
  INSERT INTO public.ranking_cache
    (user_id, name, total_points, exact_count, partial_count, negative_count, missed_count, position, updated_at)
  SELECT
    out_user_id, out_name, out_total_points, out_exact_count, out_partial_count,
    out_negative_count, out_missed_count, out_position, now()
  FROM _rk;
END;
$function$;

-- ============ 4. get_user_rank from cache ============
CREATE OR REPLACE FUNCTION public.get_user_rank(p_user_id uuid)
RETURNS TABLE(user_position integer, total_points bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT position AS user_position, total_points
  FROM public.ranking_cache
  WHERE user_id = p_user_id
  LIMIT 1;
$function$;

-- ============ 5. get_ranking_with_change: cache when no group filter ============
CREATE OR REPLACE FUNCTION public.get_ranking_with_change(p_group_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(out_user_id uuid, out_name text, out_total_points bigint, out_exact_count bigint, out_partial_count bigint, out_negative_count bigint, out_missed_count bigint, out_position integer, out_position_change integer)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  (SELECT
    c.user_id, c.name, c.total_points, c.exact_count, c.partial_count,
    c.negative_count, c.missed_count, c.position,
    CASE WHEN s.previous_position IS NULL THEN NULL
         ELSE (s.previous_position - c.position) END
  FROM public.ranking_cache c
  LEFT JOIN public.ranking_position_state s ON s.user_id = c.user_id
  WHERE p_group_id IS NULL
  ORDER BY c.position, c.name)
  UNION ALL
  (SELECT
    r.out_user_id, r.out_name, r.out_total_points, r.out_exact_count, r.out_partial_count,
    r.out_negative_count, r.out_missed_count, r.out_position,
    CASE WHEN s.previous_position IS NULL THEN NULL
         ELSE (s.previous_position - r.out_position) END
  FROM public.get_ranking(NULL, p_group_id, FALSE) r
  LEFT JOIN public.ranking_position_state s ON s.user_id = r.out_user_id
  WHERE p_group_id IS NOT NULL);
$function$;

-- ============ 6. Seed the cache ============
SELECT public.refresh_ranking_state();
