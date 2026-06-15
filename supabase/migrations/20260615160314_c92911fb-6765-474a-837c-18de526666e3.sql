CREATE OR REPLACE FUNCTION public.refresh_ranking_state()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  TRUNCATE TABLE public.ranking_cache;
  INSERT INTO public.ranking_cache
    (user_id, name, total_points, exact_count, partial_count, negative_count, missed_count, position, updated_at)
  SELECT
    out_user_id, out_name, out_total_points, out_exact_count, out_partial_count,
    out_negative_count, out_missed_count, out_position, now()
  FROM _rk;
END;
$$;