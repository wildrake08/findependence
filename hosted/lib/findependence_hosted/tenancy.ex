defmodule FindependenceHosted.Tenancy do
  @moduledoc """
  Platform context Tenancy for the hosted form (DP-001 section 2; ARCH-003 14; WI-073): creating a household,
  one-time invitation codes, and joining (REQ-185, REV-094 H3). The household always comes from the member's
  session, never from the request (REQ-186 AC-1); another household's identifiers are treated as not found.
  A membership's id is the member inside the domain rules; its display name is unique within the household
  (REV-097 F1). Invitation gives membership, not access: every item stays governed by its owners (PRI-002).
  Nothing is sent by email (REQ-185 AC-4).
  """

  import Ecto.Query
  alias FindependenceHosted.{Audit, Domain, Limits, Repo, Sessions}
  alias FindependenceHosted.Schemas.{Household, Invitation, Membership}
  alias FindependenceShared.Names

  @code_bytes 10
  @lifetime_s 72 * 60 * 60
  @max_open 5

  @doc """
  The trusted scope for a signed-in member of a household (ARCH-003 7; WI-074): their view of the household,
  built from the session the server holds, never from the request. The web layer reaches the domain contexts
  only through this, not through the storage (REQ-188 AC-2).
  """
  def scope(%{membership: %{}} = session),
    do: session |> Domain.view() |> FindependenceShared.Scope.new()

  @doc "Creates a household with the signed-in person as its first member (REQ-185 AC-1)."
  def create_household(
        token,
        %{account_id: account_id, public_key: pub, membership: nil},
        display_name
      ) do
    with {:ok, name} <- display_name(display_name) do
      {:ok, m} =
        Repo.transaction(fn ->
          household = Repo.insert!(%Household{})
          mid = Ecto.UUID.generate()

          Repo.insert!(
            struct!(
              %Membership{
                id: mid,
                household_id: household.id,
                account_id: account_id,
                display_name: name
              },
              Domain.membership_keys(household.id, mid, pub)
            )
          )
        end)

      remember(token, m)

      Audit.record("household_created", :ok, %{
        account_id: account_id,
        household_id: m.household_id
      })

      {:ok, m}
    end
  end

  def create_household(_token, _session, _name),
    do: {:error, :permanent_domain_rejection, :already_member}

  @doc """
  A new one-time code for the member's household, shown once to its creator and stored only as a hash
  (REQ-185 AC-2). At most 5 open codes per member (REQ-190 AC-2).
  """
  def create_invitation(%{account_id: a, membership: %{id: m, household_id: h}}) do
    if length(open_invitations(m, h)) >= @max_open do
      Audit.record("invitation_created", :refused, %{account_id: a, household_id: h})
      {:error, :rate_limited, :too_many_open_invitations}
    else
      code = :crypto.strong_rand_bytes(@code_bytes)

      invitation =
        Repo.insert!(%Invitation{
          household_id: h,
          created_by: m,
          code_hash: :crypto.hash(:sha256, code),
          expires_at: DateTime.add(now(), @lifetime_s) |> DateTime.truncate(:second)
        })

      Audit.record("invitation_created", :ok, %{
        account_id: a,
        household_id: h,
        resource_id: invitation.id
      })

      {:ok, format(code), invitation}
    end
  end

  @doc "The member's own open invitations: when each expires; the codes themselves are never shown again."
  def my_open_invitations(%{membership: %{id: m, household_id: h}}), do: open_invitations(m, h)

  defp open_invitations(m, h) do
    Repo.all(
      from i in Invitation,
        where:
          i.created_by == ^m and i.household_id == ^h and is_nil(i.used_at) and
            is_nil(i.withdrawn_at) and i.expires_at > ^now(),
        order_by: i.inserted_at
    )
  end

  @doc "Withdraws one of the member's own invitations; anyone else's is not found (REQ-186 AC-1)."
  def withdraw_invitation(%{account_id: a, membership: %{id: m, household_id: h}}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Invitation{} = i <-
           Repo.one(
             from i in Invitation,
               where:
                 i.id == ^id and i.created_by == ^m and i.household_id == ^h and is_nil(i.used_at) and
                   is_nil(i.withdrawn_at)
           ) do
      i |> Ecto.Changeset.change(withdrawn_at: now()) |> Repo.update!()

      Audit.record("invitation_withdrawn", :ok, %{
        account_id: a,
        household_id: h,
        resource_id: i.id
      })

      :ok
    else
      _ -> {:error, :not_found, :not_found}
    end
  end

  @doc """
  Joins a household with a code (REQ-185 AC-3). A used, expired, withdrawn, or unknown code gets one refusal
  that doesn't say which; failed attempts from one client are limited (REQ-190).
  """
  def join(token, %{account_id: a, public_key: pub, membership: nil}, code, display_name, client) do
    keys = [{:client, client}]

    cond do
      Limits.limited?(keys) ->
        {:error, :rate_limited, :too_many_attempts}

      true ->
        with {:ok, name} <- display_name(display_name),
             {:ok, bytes} <- parse(code),
             %Invitation{} = i <- usable(:crypto.hash(:sha256, bytes)) do
          Repo.transaction(fn ->
            # the household's row is locked, so the key material pins the members as they are (REV-099 G4)
            :ok = Domain.lock!(i.household_id)
            mid = Ecto.UUID.generate()
            keys = Domain.membership_keys(i.household_id, mid, pub)

            case %Membership{
                   id: mid,
                   household_id: i.household_id,
                   account_id: a,
                   display_name: name
                 }
                 |> struct!(keys)
                 |> Ecto.Changeset.change()
                 |> Ecto.Changeset.unique_constraint(:display_name,
                   name: :memberships_household_id_display_name_index
                 )
                 |> Repo.insert() do
              {:ok, m} ->
                i |> Ecto.Changeset.change(used_at: now()) |> Repo.update!()
                m

              {:error, _} ->
                Repo.rollback(:name_taken)
            end
          end)
          |> case do
            {:ok, m} ->
              remember(token, m)

              Audit.record("invitation_used", :ok, %{
                account_id: a,
                household_id: m.household_id,
                resource_id: i.id
              })

              {:ok, m}

            {:error, :name_taken} ->
              {:error, :validation,
               {:display_name,
                "Someone in this household already uses that name. Choose another."}}
          end
        else
          {:error, :validation, _} = invalid ->
            invalid

          _ ->
            Limits.failed(keys)
            Audit.record("invitation_used", :refused, %{account_id: a})
            {:error, :validation, {:code, "That code doesn't work. Ask for a new one."}}
        end
    end
  end

  def join(_token, _session, _code, _name, _client),
    do: {:error, :permanent_domain_rejection, :already_member}

  defp usable(hash) do
    Repo.one(
      from i in Invitation,
        where:
          i.code_hash == ^hash and is_nil(i.used_at) and is_nil(i.withdrawn_at) and
            i.expires_at > ^now(),
        lock: "FOR UPDATE"
    )
  end

  @doc "The display names of the member's household, in order."
  def member_names(%{membership: %{household_id: h}}) do
    Repo.all(
      from m in Membership,
        where: m.household_id == ^h,
        select: m.display_name,
        order_by: m.display_name
    )
  end

  defp remember(token, m),
    do:
      Sessions.put_membership(token, %{
        id: m.id,
        household_id: m.household_id,
        display_name: m.display_name
      })

  defp display_name(text) do
    case Names.name(text) do
      {:ok, name} -> {:ok, name}
      {:error, message} -> {:error, :validation, {:display_name, message}}
    end
  end

  defp format(bytes),
    do:
      bytes
      |> Base.encode32(padding: false)
      |> String.graphemes()
      |> Enum.chunk_every(4)
      |> Enum.map_join("-", &Enum.join/1)

  defp parse(text) do
    cleaned = text |> to_string() |> String.upcase() |> String.replace(~r/[^A-Z2-7]/, "")

    case Base.decode32(cleaned, padding: false) do
      {:ok, <<_::binary-size(@code_bytes)>> = bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
