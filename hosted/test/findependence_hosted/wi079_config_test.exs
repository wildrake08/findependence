defmodule FindependenceHosted.WI079ConfigTest do
  @moduledoc """
  WI-079: the production configuration fails closed (the security assessment's FND-13, FND-20), and the client
  address behind a trusted proxy is the forwarded one (FND-09). The production block of config/runtime.exs is
  evaluated here with chosen environment variables, which are restored afterwards.
  """
  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 2]
  alias FindependenceHostedWeb.Auth

  @vars ~w(SECRET_KEY_BASE DATABASE_URL ACCOUNT_HMAC_KEY PASSPHRASE_PEPPER HOUSEHOLD_STATE_KEY PHX_HOST DATABASE_SSL TRUSTED_PROXIES)
  @good %{
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "DATABASE_URL" => "ecto://app:pw@db.internal/findependence",
    "ACCOUNT_HMAC_KEY" => Base.encode64(:crypto.strong_rand_bytes(32)),
    # WI-085 (REQ-197, REQ-198)
    "PASSPHRASE_PEPPER" => Base.encode64(:crypto.strong_rand_bytes(32)),
    "HOUSEHOLD_STATE_KEY" => Base.encode64(:crypto.strong_rand_bytes(32)),
    "PHX_HOST" => "app.example.org"
  }

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {k, v} <- saved, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    :ok
  end

  defp prod(vars) do
    for k <- @vars, do: System.delete_env(k)
    for {k, v} <- vars, do: System.put_env(k, v)
    Config.Reader.read!("config/runtime.exs", env: :prod)
  end

  test "the database connection verifies the server's certificate by default" do
    ssl = prod(@good)[:findependence_hosted][FindependenceHosted.Repo][:ssl]
    assert ssl[:verify] == :verify_peer
    assert ssl[:server_name_indication] == ~c"db.internal"
    assert ssl[:cacerts] != []
  end

  test "an unencrypted database connection is allowed only on this host" do
    assert_raise RuntimeError, ~r/only for a database on this host/, fn ->
      prod(Map.put(@good, "DATABASE_SSL", "disable"))
    end

    local =
      @good
      |> Map.put("DATABASE_SSL", "disable")
      |> Map.put("DATABASE_URL", "ecto://app:pw@localhost/findependence")

    assert prod(local)[:findependence_hosted][FindependenceHosted.Repo][:ssl] == false
  end

  test "the host and a strong account-number hash key are required" do
    assert_raise RuntimeError, ~r/PHX_HOST is missing/, fn ->
      prod(Map.delete(@good, "PHX_HOST"))
    end

    for weak <- ["short", Base.encode64(:crypto.strong_rand_bytes(16)), "not base64 !!"] do
      assert_raise RuntimeError, ~r/ACCOUNT_HMAC_KEY must be Base64/, fn ->
        prod(Map.put(@good, "ACCOUNT_HMAC_KEY", weak))
      end
    end
  end

  test "trusted proxies are read as addresses and ranges" do
    config = prod(Map.put(@good, "TRUSTED_PROXIES", "127.0.0.1, 10.0.0.0/8,::1"))

    assert config[:findependence_hosted][:trusted_proxies] ==
             [{{127, 0, 0, 1}, 32}, {{10, 0, 0, 0}, 8}, {{0, 0, 0, 0, 0, 0, 0, 1}, 128}]

    assert_raise RuntimeError, ~r/TRUSTED_PROXIES/, fn ->
      prod(Map.put(@good, "TRUSTED_PROXIES", "not-an-address"))
    end
  end

  describe "the client address for attempt limits" do
    setup do
      on_exit(fn -> Application.delete_env(:findependence_hosted, :trusted_proxies) end)
      Application.put_env(:findependence_hosted, :trusted_proxies, [{{10, 0, 0, 0}, 8}])
      :ok
    end

    defp request(peer, forwarded) do
      c = %{conn(:get, "/") | remote_ip: peer}
      if forwarded, do: Plug.Conn.put_req_header(c, "x-forwarded-for", forwarded), else: c
    end

    test "behind a trusted proxy, the nearest untrusted forwarded address" do
      assert Auth.client(request({10, 0, 0, 5}, "198.51.100.7")) == "198.51.100.7"
      # a client's own made-up entries come first; the proxy's appended one is used
      assert Auth.client(request({10, 0, 0, 5}, "1.2.3.4, 198.51.100.7")) == "198.51.100.7"
      assert Auth.client(request({10, 0, 0, 5}, "198.51.100.7, 10.0.0.9")) == "198.51.100.7"
    end

    test "a forwarded header from anyone else is ignored" do
      assert Auth.client(request({203, 0, 113, 9}, "198.51.100.7")) == "203.0.113.9"
      assert Auth.client(request({10, 0, 0, 5}, "garbage")) == "10.0.0.5"
      assert Auth.client(request({10, 0, 0, 5}, nil)) == "10.0.0.5"
    end
  end
end
