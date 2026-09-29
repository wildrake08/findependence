defmodule FindependenceHostedWeb.SkeletonTest do
  @moduledoc "WI-063 postconditions that a test can check."
  use FindependenceHostedWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @csp "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'self'; " <>
         "img-src 'self' data:; font-src 'self'; form-action 'self'; base-uri 'none'; " <>
         "frame-ancestors 'none'; object-src 'none'"

  defp assert_security_headers(conn) do
    assert get_resp_header(conn, "content-security-policy") == [@csp]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-permitted-cross-domain-policies") == ["none"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end

  describe "security headers (ARCH-001 9.4)" do
    test "the page, the probes, a static file, and a missing page all carry them", %{conn: conn} do
      for path <- ["/", "/health/live", "/health/ready", "/robots.txt", "/no-such-page"] do
        conn = get(recycle(conn), path)
        assert_security_headers(conn)
      end
    end

    test "the policy allows only 'self', 'none', and data: images; nothing unsafe" do
      csp = FindependenceHostedWeb.SecurityHeaders.csp()
      assert csp == @csp
      refute csp =~ "unsafe"
      refute csp =~ "*"
      refute csp =~ "http"
    end

    test "the session cookie is HttpOnly and SameSite=Lax", %{conn: conn} do
      # WI-073: the specimen moved from / to /specimen; / is now the household page
      conn = get(conn, "/specimen")
      cookie = conn |> get_resp_header("set-cookie") |> Enum.join(";")
      assert cookie =~ "_findependence_hosted_key="
      assert cookie =~ ~r/HttpOnly/i
      assert cookie =~ ~r/SameSite=Lax/i
    end
  end

  describe "health (ARCH-001 9.14)" do
    test "liveness and readiness answer ok", %{conn: conn} do
      assert text_response(get(conn, "/health/live"), 200) == "ok"
      assert text_response(get(recycle(conn), "/health/ready"), 200) == "ok"
    end
  end

  describe "request bodies (ARCH-001 9.5)" do
    test "a form body over 100,000 bytes is refused", %{conn: conn} do
      body = "x=" <> String.duplicate("a", 100_001)

      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post("/", body)
      end
    end

    test "JSON and multipart bodies are refused", %{conn: conn} do
      for type <- ["application/json", "multipart/form-data; boundary=x"] do
        assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
          recycle(conn) |> put_req_header("content-type", type) |> post("/", "{}")
        end
      end
    end
  end

  describe "design specimen" do
    test "renders Petal primitives and says it keeps nothing", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/specimen")

      assert html =~ "Design specimen"
      assert html =~ "keeps nothing you enter"
      assert html =~ "Hosted edition · not in service"

      for class <- ~w(pc-button pc-alert pc-badge pc-card pc-table) do
        assert html =~ class, "expected a #{class} on the page"
      end

      assert html =~ ~r/<select[^>]*name="sample\[how_often\]"/
      assert html =~ ~r/<textarea[^>]*name="sample\[note\]"/
      assert html =~ ~r/<input[^>]*name="sample\[name\]"/
    end

    test "the form is checked on the server and nothing is kept", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/specimen")

      html = view |> form("#sample-form", sample: %{name: ""}) |> render_change()
      assert html =~ "Give it a name."

      html =
        view
        |> form("#sample-form", sample: %{name: String.duplicate("a", 201)})
        |> render_change()

      assert html =~ "200 characters or fewer"

      html = view |> form("#sample-form", sample: %{name: "Rent"}) |> render_submit()
      assert html =~ "passes the checks. Nothing was saved"
    end

    test "fields the form doesn't have are ignored (ARCH-001 3.7)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/specimen")

      html =
        render_change(view, "validate", %{"sample" => %{"name" => "Rent", "admin" => "true"}})

      refute html =~ "admin"
      assert view |> element("#sample-form") |> render() =~ ~s(value="Rent")
    end

    test "text entered is shown escaped (ARCH-001 3.8)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/specimen")

      html =
        view |> form("#sample-form", sample: %{name: "<script>x</script>"}) |> render_change()

      refute html =~ "<script>x</script>"
      assert html =~ "&lt;script&gt;x&lt;/script&gt;"
    end
  end
end
