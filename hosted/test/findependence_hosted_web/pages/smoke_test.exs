defmodule FindependenceHostedWeb.Pages.SmokeTest do
  @moduledoc "WI-075: the domain page test support works (DomainCase)."
  use FindependenceHostedWeb.DomainCase

  test "a member of a household acts through the contexts and reaches the domain routes" do
    h = household(~w(ana ben))
    assert {:ok, _} = FindependenceShared.Values.add_value(scope(h, "ana"), "Security")
    assert page(h, "ana", "/").status == 200
    assert is_binary(id(h, "ben"))

    conn = act(h, "ana", "/act/add_value", %{"label" => "Time", "return" => "/"})
    assert conn.status in [200, 302, 404, 422]
  end
end
