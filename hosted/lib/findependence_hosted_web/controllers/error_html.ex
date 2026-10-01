defmodule FindependenceHostedWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use FindependenceHostedWeb, :html

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/findependence_hosted_web/controllers/error_html/404.html.heex
  #   * lib/findependence_hosted_web/controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  # REQ-198 (WI-085): a household whose records were changed outside the service
  def render("409.html", _assigns),
    do:
      "Your household's records were changed outside this service, so nothing in it can be shown or " <>
        "changed until the service's operator restores them. This has been recorded."

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
