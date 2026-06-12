CREATE OR REPLACE FUNCTION public.admin_approve_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  UPDATE public.profiles SET is_approved = true WHERE user_id = p_user_id;

  -- Para cada partida já iniciada ou finalizada em que a pessoa NÃO palpitou,
  -- insere -2 (perdeu o palpite). is_provisional reflete o estado da partida.
  INSERT INTO public.scores (user_id, match_id, points, is_provisional)
  SELECT p_user_id, m.id, -2, (NOT m.is_finished)
  FROM public.matches m
  WHERE (m.is_started = true OR m.is_finished = true)
    AND NOT EXISTS (
      SELECT 1 FROM public.predictions pr
      WHERE pr.match_id = m.id AND pr.user_id = p_user_id
    )
  ON CONFLICT (user_id, match_id) DO NOTHING;

  PERFORM public.refresh_ranking_state();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_unapprove_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Permission denied: admin role required';
  END IF;

  UPDATE public.profiles SET is_approved = false WHERE user_id = p_user_id;

  -- Remove penalidades de -2 (sem palpite). Pontuações reais de palpites permanecem.
  DELETE FROM public.scores s
  WHERE s.user_id = p_user_id
    AND s.points = -2
    AND NOT EXISTS (
      SELECT 1 FROM public.predictions pr
      WHERE pr.match_id = s.match_id AND pr.user_id = p_user_id
    );

  PERFORM public.refresh_ranking_state();
END;
$$;