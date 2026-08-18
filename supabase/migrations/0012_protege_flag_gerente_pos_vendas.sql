-- Defesa em profundidade: só admin_geral pode alterar a flag gerente_pos_vendas de um perfil,
-- mesmo que a RLS de profiles hoje permita admin_area editar outros campos de usuários da
-- própria filial (a flag é uma autoridade que vale pra empresa toda, não por filial).
create or replace function public.fn_validate_admin_area_profile_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor public.user_type;
begin
  if new.gerente_pos_vendas is distinct from old.gerente_pos_vendas and not private.is_admin_geral() then
    raise exception 'Só um administrador geral pode designar o Gerente de Pós-Vendas.';
  end if;

  select user_type into v_actor from public.profiles where id = auth.uid();
  if v_actor = 'admin_area' then
    if old.user_type = 'admin_geral' then
      raise exception 'Um administrador de filial não pode editar um administrador geral.';
    end if;
    if new.user_type = 'admin_geral' then
      raise exception 'Um administrador de filial não pode promover ninguém a administrador geral.';
    end if;
    if old.filial_id is distinct from private.my_filial_id() then
      raise exception 'Você só pode editar usuários da sua própria filial.';
    end if;
    if new.filial_id is distinct from private.my_filial_id() then
      raise exception 'Você não pode mover um usuário para outra filial.';
    end if;
  end if;
  return new;
end; $$;
