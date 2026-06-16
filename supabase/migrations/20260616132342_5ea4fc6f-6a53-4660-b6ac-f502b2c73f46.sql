
-- 1) Snapshot table
CREATE TABLE public.ranking_kickoff_snapshots (
  block_time timestamptz NOT NULL,
  user_id uuid NOT NULL,
  position int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (block_time, user_id)
);
CREATE INDEX idx_ranking_kickoff_snapshots_block_time_desc
  ON public.ranking_kickoff_snapshots (block_time DESC);

GRANT SELECT ON public.ranking_kickoff_snapshots TO authenticated;
GRANT ALL ON public.ranking_kickoff_snapshots TO service_role;

ALTER TABLE public.ranking_kickoff_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read kickoff snapshots"
  ON public.ranking_kickoff_snapshots
  FOR SELECT TO authenticated
  USING (true);

-- 2) ensure_kickoff_snapshot: cria snapshot uma única vez por block_time
CREATE OR REPLACE FUNCTION public.ensure_kickoff_snapshot(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_block timestamptz;
BEGIN
  SELECT date_trunc('minute', match_datetime) INTO v_block
  FROM public.matches WHERE id = p_match_id;

  IF v_block IS NULL THEN RETURN; END IF;

  -- Se já existe snapshot para este bloco, não faz nada (partidas simultâneas)
  IF EXISTS (
    SELECT 1 FROM public.ranking_kickoff_snapshots WHERE block_time = v_block LIMIT 1
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.ranking_kickoff_snapshots (block_time, user_id, position)
  SELECT v_block, c.user_id, c.position
  FROM public.ranking_cache c
  ON CONFLICT (block_time, user_id) DO NOTHING;
END;
$$;

-- 3) admin_start_match: tira snapshot antes de calcular pontos
CREATE OR REPLACE FUNCTION public.admin_start_match(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  -- Snapshot do ranking ANTES de aplicar qualquer pontuação provisória.
  PERFORM public.ensure_kickoff_snapshot(p_match_id);

  UPDATE public.matches
    SET is_started = true,
        home_score = COALESCE(home_score, 0),
        away_score = COALESCE(away_score, 0)
    WHERE id = p_match_id;

  PERFORM public.calculate_live_scores(p_match_id);
  PERFORM public.refresh_ranking_state();
END;
$$;

-- 4) admin_restart_match: apaga snapshot se não restar nenhum jogo iniciado no bloco
CREATE OR REPLACE FUNCTION public.admin_restart_match(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_block timestamptz;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  SELECT date_trunc('minute', match_datetime) INTO v_block
  FROM public.matches WHERE id = p_match_id;

  DELETE FROM public.scores WHERE match_id = p_match_id;
  UPDATE public.matches
    SET is_started = false, is_finished = false, home_score = NULL, away_score = NULL
    WHERE id = p_match_id;

  -- Se nenhuma outra partida do mesmo bloco está iniciada/finalizada, remove o snapshot.
  IF v_block IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.matches m
    WHERE date_trunc('minute', m.match_datetime) = v_block
      AND m.id <> p_match_id
      AND (m.is_started = true OR m.is_finished = true)
  ) THEN
    DELETE FROM public.ranking_kickoff_snapshots WHERE block_time = v_block;
  END IF;

  PERFORM public.refresh_ranking_state();
END;
$$;

-- 5) get_ranking_with_change: usa snapshot do bloco mais recente
CREATE OR REPLACE FUNCTION public.get_ranking_with_change(p_group_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(
  out_user_id uuid, out_name text, out_total_points bigint,
  out_exact_count bigint, out_partial_count bigint, out_negative_count bigint,
  out_missed_count bigint, out_position integer, out_position_change integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH active_block AS (
    SELECT MAX(block_time) AS bt FROM public.ranking_kickoff_snapshots
  )
  (SELECT
     c.user_id, c.name, c.total_points, c.exact_count, c.partial_count,
     c.negative_count, c.missed_count, c.position,
     CASE WHEN s.position IS NULL THEN NULL
          ELSE (s.position - c.position) END
   FROM public.ranking_cache c
   LEFT JOIN public.ranking_kickoff_snapshots s
          ON s.user_id = c.user_id
         AND s.block_time = (SELECT bt FROM active_block)
   WHERE p_group_id IS NULL
   ORDER BY c.position, c.name)
  UNION ALL
  (SELECT
     r.out_user_id, r.out_name, r.out_total_points, r.out_exact_count, r.out_partial_count,
     r.out_negative_count, r.out_missed_count, r.out_position,
     NULL::int
   FROM public.get_ranking(NULL, p_group_id, FALSE) r
   WHERE p_group_id IS NOT NULL);
$$;

-- 6) refresh_ranking_state: para de escrever em ranking_position_state (economia de I/O)
CREATE OR REPLACE FUNCTION public.refresh_ranking_state()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  TRUNCATE TABLE public.ranking_cache;
  INSERT INTO public.ranking_cache
    (user_id, name, total_points, exact_count, partial_count, negative_count, missed_count, position, updated_at)
  SELECT
    out_user_id, out_name, out_total_points, out_exact_count, out_partial_count,
    out_negative_count, out_missed_count, out_position, now()
  FROM public.get_ranking(NULL, NULL, FALSE);
END;
$$;
