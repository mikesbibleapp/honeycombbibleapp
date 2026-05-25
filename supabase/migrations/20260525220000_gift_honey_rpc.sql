create or replace function public.gift_honey(
  p_recipient_id uuid,
  p_amount integer
)
returns table(sender_honey integer, transferred integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  my_honey integer;
  their_honey integer;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;

  if p_recipient_id is null then
    raise exception 'pick someone to receive the gift';
  end if;

  if uid = p_recipient_id then
    raise exception 'cannot gift yourself';
  end if;

  if p_amount is null or p_amount < 1 then
    raise exception 'amount must be positive';
  end if;

  select coalesce((state->>'honey')::integer, 0)
    into my_honey
    from public.user_progress
    where user_id = uid
    for update;

  if my_honey is null then
    raise exception 'sender progress not found';
  end if;

  if my_honey < p_amount then
    raise exception 'not enough honey';
  end if;

  select coalesce((state->>'honey')::integer, 0)
    into their_honey
    from public.user_progress
    where user_id = p_recipient_id
    for update;

  if their_honey is null then
    raise exception 'recipient not found';
  end if;

  update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(my_honey - p_amount), true),
        updated_at = now()
    where user_id = uid;

  update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(their_honey + p_amount), true),
        updated_at = now()
    where user_id = p_recipient_id;

  return query select (my_honey - p_amount), p_amount;
end;
$$;

grant execute on function public.gift_honey(uuid, integer) to authenticated;
