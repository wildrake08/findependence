defmodule FindependenceHostedWeb.BodyParsers do
  @moduledoc """
  Request bodies, as the local form reads them (WI-076, REV-103 I2; REQ-157 AC-1, REQ-190 AC-3): forms are
  urlencoded, at most 100 kB (WI-073). Only bringing in a record accepts a file, up to 1 MB of export plus the
  form's own overhead; anything larger is refused before it is read in full, with the local form's page.
  """
  @behaviour Plug
  import Plug.Conn

  @form_parsers Plug.Parsers.init(parsers: [:urlencoded], pass: [], length: 100_000)
  @upload_parsers Plug.Parsers.init(
                    parsers: [:urlencoded, :multipart],
                    pass: [],
                    length: 1_100_000
                  )

  @doc "The largest export file that is read (REQ-157 AC-1)."
  def max_upload, do: 1_048_576

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: "POST", path_info: ["act", "bring-in"]} = conn, _opts) do
    Plug.Parsers.call(conn, @upload_parsers)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(
        413,
        ~s(<!doctype html><html lang=en><head><meta charset=utf-8><title>Findependence</title></head><body><main><h1>That file is too large</h1><p>An export file is at most 1 MB, so this one wasn't read. Nothing was brought in.</p><p><a href="/bring-in">Back</a></p></main></body></html>)
      )
      |> halt()
  end

  def call(conn, _opts), do: Plug.Parsers.call(conn, @form_parsers)
end
