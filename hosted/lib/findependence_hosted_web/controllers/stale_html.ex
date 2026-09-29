defmodule FindependenceHostedWeb.StaleHTML do
  @moduledoc "The page for a form that was out of date (WI-075; the local form's DEF-035 wording)."
  use FindependenceHostedWeb, :html

  def stale(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current={@current}>
      <.alert variant="soft" color="warning" heading="That wasn't saved" role="alert">
        This page was out of date, so nothing was saved. Go to the home page and do it again.
      </.alert>
      <.p><.link href={~p"/"}>Go to the home page</.link></.p>
    </Layouts.app>
    """
  end
end
