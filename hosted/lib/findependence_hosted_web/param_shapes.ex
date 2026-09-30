defmodule FindependenceHostedWeb.ParamShapes do
  @moduledoc """
  Refuses a request whose parameters don't have the shapes the forms send (WI-079, the security assessment's
  FND-12): every field is text, except the lists of chosen owners, members, and items, the account, join, and
  household forms (text fields under one name), and the bring-in file. A field sent as a list or map where text
  is expected used to reach decoding code and fail there with an error; now the request is refused with 400
  before any controller runs, and nothing changes.
  """
  @behaviour Plug
  import Plug.Conn

  @lists ~w(owners members items)
  @forms ~w(account join household)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Enum.all?(conn.params, &allowed?/1) do
      conn
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(
        400,
        ~s(<!doctype html><html lang=en><head><meta charset=utf-8><title>Findependence</title></head><body><main><h1>That request can't be read</h1><p>Nothing was changed.</p><p><a href="/">Back</a></p></main></body></html>)
      )
      |> halt()
    end
  end

  @doc false
  def allowed?({_key, value}) when is_binary(value), do: true
  def allowed?({"file", %Plug.Upload{}}), do: true

  def allowed?({key, list}) when key in @lists and is_list(list),
    do: Enum.all?(list, &is_binary/1)

  def allowed?({key, %{} = form}) when key in @forms and not is_struct(form),
    do: Enum.all?(form, fn {k, v} -> is_binary(k) and is_binary(v) end)

  def allowed?(_), do: false
end
