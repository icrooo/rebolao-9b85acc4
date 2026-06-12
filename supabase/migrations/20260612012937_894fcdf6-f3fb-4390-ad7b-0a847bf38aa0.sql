CREATE OR REPLACE FUNCTION public.get_user_rank(p_user_id uuid)
RETURNS TABLE(user_position integer, total_points bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT r.out_position AS user_position,
         r.out_total_points AS total_points
  FROM public.get_ranking(NULL, NULL, FALSE) r
  WHERE r.out_user_id = p_user_id
  LIMIT 1;
$$;